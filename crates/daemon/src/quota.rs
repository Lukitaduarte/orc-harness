//! Rate limits per account, fed by Claude Code's statusLine.
//!
//! The quota belongs to the account, not to the session: any session of the
//! account updates it. Claude Code omits `rate_limits` before the first API
//! response and for non-subscribers, so a report without them never clears
//! what is known; the last reading stays, with its time.

use std::collections::HashMap;

use orc_protocol::{QuotaWindow, RateLimits, StatusReport};

#[derive(Debug, Clone, PartialEq)]
pub struct AccountQuota {
    pub limits: RateLimits,
    /// Unix seconds of the last reading that carried rate limits.
    pub read_at: i64,
}

#[derive(Debug, Default)]
pub struct QuotaStore {
    accounts: HashMap<String, AccountQuota>,
}

impl QuotaStore {
    /// Applies a report. Returns the account's quota when it changed.
    pub fn ingest(&mut self, report: &StatusReport) -> Option<&AccountQuota> {
        let incoming = report.rate_limits.as_ref()?;
        if incoming.five_hour.is_none() && incoming.seven_day.is_none() {
            return None;
        }
        let entry = self
            .accounts
            .entry(report.account_id.clone())
            .or_insert_with(|| AccountQuota { limits: RateLimits::default(), read_at: 0 });
        // Out-of-order reports (two sessions of one account) never roll back.
        if report.read_at < entry.read_at {
            return None;
        }
        // A window missing from this report keeps its previous value.
        entry.limits.five_hour = incoming.five_hour.or(entry.limits.five_hour);
        entry.limits.seven_day = incoming.seven_day.or(entry.limits.seven_day);
        entry.read_at = report.read_at;
        Some(entry)
    }

    pub fn get(&self, account_id: &str) -> Option<&AccountQuota> {
        self.accounts.get(account_id)
    }
}

/// Short text for the statusLine itself: "5h 62% · 7d 38%".
pub fn status_text(limits: &RateLimits) -> String {
    let part = |label: &str, w: &Option<QuotaWindow>| {
        w.map(|w| format!("{label} {:.0}%", w.used_percentage))
    };
    [part("5h", &limits.five_hour), part("7d", &limits.seven_day)]
        .into_iter()
        .flatten()
        .collect::<Vec<_>>()
        .join(" · ")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn report(account: &str, five: Option<f64>, seven: Option<f64>, at: i64) -> StatusReport {
        let w = |p| QuotaWindow { used_percentage: p, resets_at: 1_000 };
        StatusReport {
            account_id: account.into(),
            session_id: "s".into(),
            rate_limits: (five.is_some() || seven.is_some()).then(|| RateLimits {
                five_hour: five.map(w),
                seven_day: seven.map(w),
            }),
            cost_usd: None,
            tokens: None,
            read_at: at,
        }
    }

    #[test]
    fn keeps_the_last_reading_when_a_report_has_no_limits() {
        let mut q = QuotaStore::default();
        q.ingest(&report("work", Some(62.0), Some(38.0), 10));
        assert!(q.ingest(&report("work", None, None, 20)).is_none());
        let a = q.get("work").unwrap();
        assert_eq!(a.limits.five_hour.unwrap().used_percentage, 62.0);
        assert_eq!(a.read_at, 10);
    }

    #[test]
    fn a_missing_window_keeps_its_value() {
        let mut q = QuotaStore::default();
        q.ingest(&report("work", Some(62.0), Some(38.0), 10));
        q.ingest(&report("work", Some(70.0), None, 20));
        let a = q.get("work").unwrap();
        assert_eq!(a.limits.five_hour.unwrap().used_percentage, 70.0);
        assert_eq!(a.limits.seven_day.unwrap().used_percentage, 38.0);
    }

    #[test]
    fn older_reports_do_not_roll_back_and_accounts_are_separate() {
        let mut q = QuotaStore::default();
        q.ingest(&report("work", Some(70.0), None, 20));
        q.ingest(&report("work", Some(50.0), None, 15));
        q.ingest(&report("personal", Some(8.0), None, 15));
        assert_eq!(q.get("work").unwrap().limits.five_hour.unwrap().used_percentage, 70.0);
        assert_eq!(q.get("personal").unwrap().limits.five_hour.unwrap().used_percentage, 8.0);
    }

    #[test]
    fn status_text_shows_what_is_known() {
        let r = report("work", Some(62.4), Some(38.0), 1).rate_limits.unwrap();
        assert_eq!(status_text(&r), "5h 62% · 7d 38%");
        let only5 = report("work", Some(9.0), None, 1).rate_limits.unwrap();
        assert_eq!(status_text(&only5), "5h 9%");
    }
}
