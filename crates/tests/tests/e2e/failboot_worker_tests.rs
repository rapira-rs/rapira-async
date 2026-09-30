use std::time::{Duration, Instant};

use rapira_sapi::Mode;
use tests::wire::submit;
use tests::{drain_resp_deadline, fixture, req};

use crate::harness::{MASTER_EXIT_FAILBOOT, MASTER_EXIT_OK, Spawn, assert_exit_code, signal};

// A worker that fatals before its receive loop must 503 the queued job, and the graceful stop must not wait on a boot that retries forever.
#[test]
fn failboot_worker_serves_503_and_drops_cleanly() -> anyhow::Result<()> {
    let mut srv = Spawn::http(
        Mode::Dispatcher,
        fixture("failboot_worker_tests/failboot-worker.php"),
    )
    .spawn();
    let deadline = Instant::now() + Duration::from_secs(10);

    let mut rx = submit(srv.addr, req("/"))?;
    let resp = drain_resp_deadline(&mut rx, deadline)
        .expect("broken worker black-holed the request (A6 regression)");
    assert_eq!(
        resp.status(),
        503,
        "a boot-failed worker must 503 the queued job"
    );

    signal(srv.pid(), libc::SIGQUIT);
    let status = srv.wait_exit(deadline.saturating_duration_since(Instant::now()));
    assert_exit_code(status, MASTER_EXIT_OK, &srv);
    Ok(())
}

// UNHEALTHY_AFTER (5) consecutive boot failures must flag the worker unhealthy, each failed boot 503ing its queued job.
// The boot runs failed cycle 1. The 4 requests arrive before the 5 s boot retry, so each shed job starts the next cycle, and cycle 5 follows job 4 and flags the worker. The flag stops the worker, and the master failboots because the gen-0 pool never served.
#[test]
fn failboot_worker_flags_unhealthy_after_threshold() -> anyhow::Result<()> {
    let mut srv = Spawn::http(
        Mode::Dispatcher,
        fixture("failboot_worker_tests/failboot-worker.php"),
    )
    .spawn();
    let deadline = Instant::now() + Duration::from_secs(15);

    let mut statuses = Vec::new();
    for _ in 0..4 {
        let mut rx = submit(srv.addr, req("/"))?;
        let resp = drain_resp_deadline(&mut rx, deadline)
            .expect("boot-failing worker hung (unhealthy regression)");
        statuses.push(resp.status());
    }
    assert!(
        statuses.iter().all(|&s| s == 503),
        "each boot-failed job must 503 (got {statuses:?})"
    );

    let status = srv.wait_exit(deadline.saturating_duration_since(Instant::now()));
    assert_exit_code(status, MASTER_EXIT_FAILBOOT, &srv);
    let log = std::fs::read_to_string(srv.log_file())?;
    assert!(
        log.contains("worker keeps failing to boot; flagged unhealthy"),
        "5 consecutive boot failures must flag the worker unhealthy\n{log}"
    );
    Ok(())
}
