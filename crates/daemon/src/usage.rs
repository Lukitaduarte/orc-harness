//! Token and cost usage from Claude Code's OpenTelemetry metrics.
//!
//! Each session runs with OTLP/HTTP-JSON pointed at the daemon and its
//! resource tagged `orc.session` / `orc.account`. Metrics are deltas (the
//! default), so every data point is added. Points are kept in `orc.db`
//! (table `usage`); per-session totals are rebuilt from it on start.

use std::collections::HashMap;
use std::path::PathBuf;

use crate::db::{Db, Value as DbValue, opt, opt_text, real, t, text};

use orc_protocol::{Usage, UsageRow};
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// One data point, as stored.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Point {
    pub day: String,
    pub session_id: String,
    pub account_id: String,
    pub model: String,
    /// input, output, cacheRead, cacheCreation or cost.
    pub kind: String,
    pub value: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub project: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub branch: Option<String>,
}


pub struct UsageStore {
    db: Db,
    /// Totals per session, kept in memory (asked on every export).
    by_session: HashMap<String, Usage>,
}

fn add(u: &mut Usage, kind: &str, v: f64) {
    match kind {
        "input" => u.input += v as u64,
        "output" => u.output += v as u64,
        "cacheRead" => u.cache_read += v as u64,
        "cacheCreation" => u.cache_creation += v as u64,
        "cost" => u.cost_usd += v,
        _ => {}
    }
}

const SCHEMA: &str = "CREATE TABLE IF NOT EXISTS usage (
    day TEXT NOT NULL, session TEXT NOT NULL, account TEXT NOT NULL, model TEXT NOT NULL,
    project TEXT, branch TEXT, kind TEXT NOT NULL, value REAL NOT NULL);
CREATE INDEX IF NOT EXISTS usage_day ON usage (day);";

impl UsageStore {
    /// Usage in `orc.db` next to `log`; the points of an old `log`
    /// (usage.jsonl) move into it once and the file is renamed `.imported`.
    pub fn load(log: PathBuf) -> Self {
        let db = Db::open(&log.with_file_name("orc.db")).unwrap_or_else(|e| {
            eprintln!("orcd: {e}; uso só em memória nesta execução");
            Db::memory()
        });
        Self::open(db, Some(log))
    }

    pub fn open(db: Db, legacy: Option<PathBuf>) -> Self {
        if let Err(e) = db.batch(SCHEMA) {
            eprintln!("orcd: tabela de uso: {e}");
        }
        let mut s = Self { db, by_session: HashMap::new() };
        if let Some(log) = legacy.filter(|l| l.exists()) {
            let points: Vec<Point> = std::fs::read_to_string(&log)
                .unwrap_or_default()
                .lines()
                .filter_map(|l| serde_json::from_str(l).ok())
                .collect();
            if s.insert(&points).is_ok() {
                let _ = std::fs::rename(&log, log.with_extension("jsonl.imported"));
            }
        }
        let rows = s.db.query("SELECT session, kind, SUM(value) FROM usage GROUP BY session, kind", vec![]).unwrap_or_default();
        for r in rows {
            add(s.by_session.entry(text(&r[0])).or_default(), &text(&r[1]), real(&r[2]));
        }
        s
    }

    /// The database, for the other stores that live in it.
    pub fn db(&self) -> Db {
        self.db.clone()
    }

    fn insert(&self, points: &[Point]) -> std::io::Result<()> {
        for p in points {
            self.db.exec(
                "INSERT INTO usage (day, session, account, model, project, branch, kind, value) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                vec![t(&p.day), t(&p.session_id), t(&p.account_id), t(&p.model), opt(&p.project), opt(&p.branch), t(&p.kind), DbValue::Real(p.value)],
            )?;
        }
        Ok(())
    }

    /// Records points; returns the sessions whose totals changed.
    pub fn record(&mut self, points: &[Point]) -> Vec<(String, Usage)> {
        if points.is_empty() {
            return Vec::new();
        }
        if let Err(e) = self.insert(points) {
            eprintln!("orcd: não gravei uso: {e}");
        }
        let mut changed = Vec::new();
        for p in points {
            add(self.by_session.entry(p.session_id.clone()).or_default(), &p.kind, p.value);
            if !changed.contains(&p.session_id) {
                changed.push(p.session_id.clone());
            }
        }
        changed.into_iter().map(|id| { let u = self.by_session[&id]; (id, u) }).collect()
    }

    pub fn session(&self, id: &str) -> Usage {
        self.by_session.get(id).copied().unwrap_or_default()
    }

    /// Rows from `since_day` (YYYY-MM-DD) on, oldest first: per day,
    /// account, model, project and branch.
    pub fn report(&self, since_day: &str) -> Vec<UsageRow> {
        let rows = self
            .db
            .query(
                "SELECT day, account, model, project, branch, kind, SUM(value) FROM usage WHERE day >= ?1 \
                 GROUP BY day, account, model, project, branch, kind ORDER BY day, account, model, project, branch",
                vec![t(since_day)],
            )
            .unwrap_or_default();
        let mut out: Vec<UsageRow> = Vec::new();
        for r in rows {
            let key = (text(&r[0]), text(&r[1]), text(&r[2]), opt_text(&r[3]), opt_text(&r[4]));
            let same = out.last().is_some_and(|l| (l.day.clone(), l.account_id.clone(), l.model.clone(), l.project_id.clone(), l.branch.clone()) == key);
            if !same {
                out.push(UsageRow { day: key.0, account_id: key.1, model: key.2, project_id: key.3, branch: key.4, usage: Usage::default() });
            }
            add(&mut out.last_mut().expect("pushed").usage, &text(&r[5]), real(&r[6]));
        }
        out
    }
}

/// UTC day of a Unix time in nanoseconds (days since epoch → civil date).
pub fn day_of(nanos: u128) -> String {
    let days = (nanos / 1_000_000_000 / 86_400) as i64;
    // Howard Hinnant's civil_from_days.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02}")
}

fn attr<'a>(attrs: &'a Value, key: &str) -> Option<&'a str> {
    attrs.as_array()?.iter().find(|a| a["key"] == key)?["value"]["stringValue"].as_str()
}

/// Reads an OTLP/JSON metrics export into usage points. Only Claude Code's
/// token and cost metrics from sessions tagged by the daemon count.
pub fn parse_otlp(body: &Value) -> Vec<Point> {
    let mut out = Vec::new();
    for rm in body["resourceMetrics"].as_array().into_iter().flatten() {
        let resource = &rm["resource"]["attributes"];
        for sm in rm["scopeMetrics"].as_array().into_iter().flatten() {
            for metric in sm["metrics"].as_array().into_iter().flatten() {
                let name = metric["name"].as_str().unwrap_or_default();
                if name != "claude_code.token.usage" && name != "claude_code.cost.usage" {
                    continue;
                }
                for dp in metric["sum"]["dataPoints"].as_array().into_iter().flatten() {
                    let attrs = &dp["attributes"];
                    let get = |k| attr(attrs, k).or_else(|| attr(resource, k));
                    let (Some(session), Some(account)) = (get("orc.session"), get("orc.account")) else {
                        continue;
                    };
                    let kind = if name == "claude_code.cost.usage" {
                        "cost"
                    } else {
                        get("type").unwrap_or("")
                    };
                    // asInt arrives as a string (int64 in JSON), asDouble as a number.
                    let value = dp["asDouble"]
                        .as_f64()
                        .or_else(|| dp["asInt"].as_str().and_then(|s| s.parse().ok()))
                        .or_else(|| dp["asInt"].as_f64())
                        .unwrap_or(0.0);
                    let nanos = dp["timeUnixNano"]
                        .as_str()
                        .and_then(|s| s.parse::<u128>().ok())
                        .or_else(|| dp["timeUnixNano"].as_u64().map(u128::from))
                        .unwrap_or(0);
                    out.push(Point {
                        day: day_of(nanos),
                        session_id: session.into(),
                        account_id: account.into(),
                        model: get("model").unwrap_or("?").into(),
                        kind: kind.into(),
                        value,
                        project: get("orc.project").map(String::from),
                        branch: get("orc.branch").map(String::from),
                    });
                }
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn export(session: &str, kind: &str, metric: &str, value: Value) -> Value {
        json!({ "resourceMetrics": [{
            "resource": { "attributes": [
                { "key": "orc.session", "value": { "stringValue": session } },
                { "key": "orc.account", "value": { "stringValue": "work" } } ] },
            "scopeMetrics": [{ "metrics": [{
                "name": metric,
                "sum": { "aggregationTemporality": 1, "isMonotonic": true, "dataPoints": [{
                    "attributes": [
                        { "key": "type", "value": { "stringValue": kind } },
                        { "key": "model", "value": { "stringValue": "claude-opus-5-5" } } ],
                    "timeUnixNano": "1793577600000000000",
                    "asDouble": value
                }] }
            }, { "name": "claude_code.lines_of_code.count", "sum": { "dataPoints": [{ "asInt": "3" }] } }] }]
        }]})
    }

    #[test]
    fn days_are_utc_civil_dates() {
        assert_eq!(day_of(0), "1970-01-01");
        assert_eq!(day_of(1_793_577_600_000_000_000), "2026-11-02");
        assert_eq!(day_of(951_782_400_000_000_000), "2000-02-29");
    }

    #[test]
    fn sums_deltas_per_session_and_day_and_survives_restart() {
        let dir = tempfile::tempdir().unwrap();
        let log = dir.path().join("usage.jsonl");
        let mut store = UsageStore::load(log.clone());
        for (kind, metric, v) in [
            ("input", "claude_code.token.usage", json!(1200)),
            ("output", "claude_code.token.usage", json!(300)),
            ("input", "claude_code.token.usage", json!(800)),
            ("", "claude_code.cost.usage", json!(0.042)),
        ] {
            let points = parse_otlp(&export("s1", kind, metric, v));
            assert_eq!(points.len(), 1, "other metrics are ignored");
            store.record(&points);
        }
        let u = store.session("s1");
        assert_eq!((u.input, u.output), (2000, 300));
        assert!((u.cost_usd - 0.042).abs() < 1e-9);

        drop(store); // one daemon at a time on the file
        let again = UsageStore::load(log.clone());
        assert_eq!(again.session("s1"), u);
        let rows = again.report("2026-11-01");
        assert_eq!(rows.len(), 1);
        assert_eq!((rows[0].day.as_str(), rows[0].model.as_str()), ("2026-11-02", "claude-opus-5-5"));
        assert!(again.report("2026-11-03").is_empty());
    }

    #[test]
    fn project_sessions_are_labeled_by_branch() {
        let dir = tempfile::tempdir().unwrap();
        let mut body = export("s2", "output", "claude_code.token.usage", json!(30.0));
        let attrs = body["resourceMetrics"][0]["resource"]["attributes"].as_array_mut().unwrap();
        attrs.push(json!({ "key": "orc.project", "value": { "stringValue": "web" } }));
        attrs.push(json!({ "key": "orc.branch", "value": { "stringValue": "feat/1-login" } }));
        let mut store = UsageStore::load(dir.path().join("u.jsonl"));
        store.record(&parse_otlp(&body));
        store.record(&parse_otlp(&export("s1", "output", "claude_code.token.usage", json!(5.0))));
        drop(store);
        let again = UsageStore::load(dir.path().join("u.jsonl"));
        let rows = again.report("2026-01-01");
        let labeled: Vec<_> = rows.iter().map(|r| (r.project_id.as_deref(), r.branch.as_deref(), r.usage.output)).collect();
        assert!(labeled.contains(&(Some("web"), Some("feat/1-login"), 30)), "{labeled:?}");
        assert!(labeled.contains(&(None, None, 5)), "{labeled:?}");
    }

    #[test]
    fn an_old_usage_log_moves_into_the_database_once() {
        let dir = tempfile::tempdir().unwrap();
        let log = dir.path().join("usage.jsonl");
        let p = Point { day: "2026-11-02".into(), session_id: "s9".into(), account_id: "w".into(), model: "m".into(), kind: "output".into(), value: 7.0, project: None, branch: None };
        std::fs::write(&log, format!("{}\n{}\n", serde_json::to_string(&p).unwrap(), serde_json::to_string(&p).unwrap())).unwrap();
        let store = UsageStore::load(log.clone());
        assert_eq!(store.session("s9").output, 14);
        assert!(!log.exists() && dir.path().join("usage.jsonl.imported").exists());
        drop(store);
        assert_eq!(UsageStore::load(log).session("s9").output, 14, "imported once");
    }

    #[test]
    fn untagged_points_and_int_values() {
        let mut body = export("s1", "output", "claude_code.token.usage", json!(null));
        body["resourceMetrics"][0]["scopeMetrics"][0]["metrics"][0]["sum"]["dataPoints"][0]["asInt"] = json!("42");
        assert_eq!(parse_otlp(&body)[0].value, 42.0);
        // Without the daemon's tags (a session it did not start): ignored.
        body["resourceMetrics"][0]["resource"]["attributes"] = json!([]);
        assert!(parse_otlp(&body).is_empty());
    }
}
