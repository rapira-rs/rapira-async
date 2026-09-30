use rapira_sapi::Mode;
use tests::wire::submit;
use tests::{drain, fixture, req};

use crate::harness::Spawn;

/// HTTP classes and the PR APIs must exist in the embed runtime after MINIT.
#[test]
fn http_and_async_php_classes_exist_after_boot() -> anyhow::Result<()> {
    let srv = Spawn::http(Mode::Worker, fixture("registry/classes.php")).spawn();
    let (status, body) = drain(submit(srv.addr, req("/"))?);
    assert_eq!(status, 200, "body: {body:?}");
    for class in [
        "Rapira\\Work",
        "Rapira\\Http\\Exchange",
        "Rapira\\Internal\\Http\\Exchange",
        "Io\\Poll\\Context",
        "Io\\Poll\\TimerHandle",
        "Io\\Hooks\\Hooks",
        "Io\\Ring\\Engine",
    ] {
        assert!(
            body.contains(&format!("{class}: yes\n")),
            "{class} missing (got {body:?})"
        );
    }
    assert!(
        body.contains("Rapira\\Internal\\Http\\Exchange extends Rapira\\Work: yes\n"),
        "Rapira\\Internal\\Http\\Exchange does not extend Rapira\\Work (got {body:?})"
    );
    Ok(())
}
