use std::sync::OnceLock;
use tokio::runtime::Runtime;

pub(crate) fn tokio_runtime() -> &'static Runtime {
  static RT: OnceLock<Runtime> = OnceLock::new();
  RT.get_or_init(|| {
    tokio::runtime::Builder::new_multi_thread()
      .enable_all()
      .build()
      .expect("tokio runtime")
  })
}
