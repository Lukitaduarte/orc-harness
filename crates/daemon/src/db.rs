//! `~/.orc/orc.db`: Turso (SQLite format) for what grows and is queried —
//! usage points and agents' memory. Turso's API is async; the daemon's
//! stores are sync, so one thread owns the connection and serves
//! statements in order through a channel.

use std::path::Path;
use std::sync::mpsc;

pub use turso::Value;

type Reply<T> = mpsc::Sender<Result<T, String>>;

enum Job {
    Exec(String, Vec<Value>, Reply<u64>),
    Query(String, Vec<Value>, Reply<Vec<Vec<Value>>>),
    Batch(String, Reply<()>),
}

/// A handle to the database thread; cheap to clone.
#[derive(Clone)]
pub struct Db {
    tx: mpsc::Sender<Job>,
}

impl Db {
    /// Opens (creating) the database file.
    pub fn open(path: &Path) -> std::io::Result<Self> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        Self::start(path.display().to_string())
    }

    /// A database in memory (tests, or a daemon without a home).
    pub fn memory() -> Self {
        Self::start(":memory:".into()).expect("in-memory database")
    }

    fn start(path: String) -> std::io::Result<Self> {
        let (tx, rx) = mpsc::channel::<Job>();
        let (ready_tx, ready_rx) = mpsc::channel::<Result<(), String>>();
        std::thread::Builder::new().name("orc-db".into()).spawn(move || {
            let rt = match tokio::runtime::Builder::new_current_thread().enable_all().build() {
                Ok(rt) => rt,
                Err(e) => return drop(ready_tx.send(Err(e.to_string()))),
            };
            let conn = rt.block_on(async {
                let db = turso::Builder::new_local(&path).build().await.map_err(|e| e.to_string())?;
                db.connect().map_err(|e| e.to_string())
            });
            let conn = match conn {
                Ok(c) => {
                    let _ = ready_tx.send(Ok(()));
                    c
                }
                Err(e) => return drop(ready_tx.send(Err(e))),
            };
            for job in rx {
                match job {
                    Job::Exec(sql, params, reply) => {
                        let r = rt.block_on(conn.execute(&sql, params)).map_err(|e| e.to_string());
                        let _ = reply.send(r);
                    }
                    Job::Batch(sql, reply) => {
                        let r = rt.block_on(conn.execute_batch(&sql)).map_err(|e| e.to_string());
                        let _ = reply.send(r);
                    }
                    Job::Query(sql, params, reply) => {
                        let r = rt.block_on(async {
                            let mut rows = conn.query(&sql, params).await?;
                            let mut out = Vec::new();
                            while let Some(row) = rows.next().await? {
                                out.push((0..row.column_count()).map(|i| row.get_value(i)).collect::<Result<Vec<_>, _>>()?);
                            }
                            Ok::<_, turso::Error>(out)
                        });
                        let _ = reply.send(r.map_err(|e| e.to_string()));
                    }
                }
            }
        })?;
        match ready_rx.recv() {
            Ok(Ok(())) => Ok(Self { tx }),
            Ok(Err(e)) => Err(std::io::Error::other(format!("banco: {e}"))),
            Err(_) => Err(std::io::Error::other("banco: a thread não subiu")),
        }
    }

    fn call<T>(&self, job: impl FnOnce(Reply<T>) -> Job) -> std::io::Result<T> {
        let (reply, rx) = mpsc::channel();
        self.tx.send(job(reply)).map_err(|_| std::io::Error::other("banco fechado"))?;
        rx.recv()
            .map_err(|_| std::io::Error::other("banco fechado"))?
            .map_err(std::io::Error::other)
    }

    /// One statement; returns the rows changed.
    pub fn exec(&self, sql: &str, params: Vec<Value>) -> std::io::Result<u64> {
        self.call(|r| Job::Exec(sql.into(), params, r))
    }

    /// Several statements, no parameters (schema).
    pub fn batch(&self, sql: &str) -> std::io::Result<()> {
        self.call(|r| Job::Batch(sql.into(), r))
    }

    pub fn query(&self, sql: &str, params: Vec<Value>) -> std::io::Result<Vec<Vec<Value>>> {
        self.call(|r| Job::Query(sql.into(), params, r))
    }
}

/// Column helpers for rows from [`Db::query`].
pub fn text(v: &Value) -> String {
    match v {
        Value::Text(s) => s.clone(),
        Value::Integer(i) => i.to_string(),
        Value::Real(f) => f.to_string(),
        _ => String::new(),
    }
}

pub fn opt_text(v: &Value) -> Option<String> {
    match v {
        Value::Null => None,
        v => Some(text(v)),
    }
}

pub fn real(v: &Value) -> f64 {
    match v {
        Value::Real(f) => *f,
        Value::Integer(i) => *i as f64,
        _ => 0.0,
    }
}

pub fn int(v: &Value) -> i64 {
    match v {
        Value::Integer(i) => *i,
        Value::Real(f) => *f as i64,
        _ => 0,
    }
}

pub fn t(s: &str) -> Value {
    Value::Text(s.into())
}

pub fn opt(s: &Option<String>) -> Value {
    s.as_deref().map(t).unwrap_or(Value::Null)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn statements_run_in_order_and_survive_reopening() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("orc.db");
        let db = Db::open(&path).unwrap();
        db.batch("CREATE TABLE kv (k TEXT PRIMARY KEY, v REAL)").unwrap();
        assert_eq!(db.exec("INSERT INTO kv VALUES (?1, ?2)", vec![t("a"), Value::Real(1.5)]).unwrap(), 1);
        db.exec("INSERT INTO kv VALUES (?1, ?2)", vec![t("b"), Value::Real(2.0)]).unwrap();
        let rows = db.query("SELECT k, v FROM kv ORDER BY k", vec![]).unwrap();
        assert_eq!(rows.iter().map(|r| (text(&r[0]), real(&r[1]))).collect::<Vec<_>>(), [("a".into(), 1.5), ("b".into(), 2.0)]);
        assert!(db.exec("INSERT INTO kv VALUES (?1, ?2)", vec![t("a"), Value::Real(0.0)]).is_err(), "constraint errors come back");
        drop(db);
        let again = Db::open(&path).unwrap();
        let sum = again.query("SELECT SUM(v) FROM kv", vec![]).unwrap();
        assert_eq!(real(&sum[0][0]), 3.5);
        // Usable from many threads.
        let handles: Vec<_> = (0..4)
            .map(|i| {
                let db = again.clone();
                std::thread::spawn(move || db.exec("INSERT INTO kv VALUES (?1, 1)", vec![t(&format!("t{i}"))]).unwrap())
            })
            .collect();
        for h in handles {
            h.join().unwrap();
        }
        assert_eq!(int(&again.query("SELECT COUNT(*) FROM kv", vec![]).unwrap()[0][0]), 6);
    }
}
