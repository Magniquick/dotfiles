pub(crate) fn load_env(env_file: &str) {
  if !env_file.trim().is_empty() {
    let _ = dotenvy::from_filename(env_file);
  } else {
    let _ = dotenvy::dotenv();
  }
}
