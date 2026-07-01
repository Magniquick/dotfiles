use std::env;
use std::path::PathBuf;
use std::process::ExitCode;

use qsnative_rust::app_config;
use qsnative_rust::google_auth;

#[derive(Debug)]
struct Options {
    account_id: String,
    config_path: PathBuf,
    client_json: String,
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("{error}");
            ExitCode::from(1)
        }
    }
}

fn run() -> Result<(), String> {
    let args = env::args().skip(1).collect::<Vec<_>>();
    let Some(command) = args.first() else {
        usage();
        return Err("subcommand is required".to_owned());
    };

    match command.as_str() {
        "provision" => provision(&args[1..]),
        "provision-all" => provision_all(&args[1..]),
        "list-calendars" => list_calendars(&args[1..]),
        _ => {
            usage();
            Err(format!("unknown subcommand {command:?}"))
        }
    }
}

fn provision(args: &[String]) -> Result<(), String> {
    let opts = parse_flags(args, false, true)?;
    let account = app_config::load_account(&opts.config_path, &opts.account_id)?;
    google_auth::provision(&account, optional_path(&opts.client_json))?;
    eprintln!(
        "stored Google OAuth refresh config for {} ({})",
        account.id, account.address
    );
    let prefix = google_auth::key_prefix(&account.id);
    eprintln!("keys: {prefix}TOKEN_JSON, {prefix}CLIENT_JSON");
    Ok(())
}

fn provision_all(args: &[String]) -> Result<(), String> {
    let opts = parse_flags(args, false, false)?;
    let accounts = app_config::load_google_accounts(&opts.config_path)?;
    if accounts.is_empty() {
        return Err("no Gmail accounts configured".to_owned());
    }
    for account in accounts {
        eprintln!("provisioning {} ({})", account.id, account.address);
        google_auth::provision(&account, optional_path(&opts.client_json))?;
        let prefix = google_auth::key_prefix(&account.id);
        eprintln!("stored keys: {prefix}TOKEN_JSON, {prefix}CLIENT_JSON");
    }
    Ok(())
}

fn list_calendars(args: &[String]) -> Result<(), String> {
    let opts = parse_flags(args, false, true)?;
    let account = app_config::load_account(&opts.config_path, &opts.account_id)?;
    let calendars = google_auth::list_calendars(&account)?;
    let raw = serde_json::to_string_pretty(&calendars).map_err(|error| error.to_string())?;
    println!("{raw}");
    Ok(())
}

fn usage() {
    eprintln!("usage: qs-google-auth provision --account ID [--client-json PATH]");
    eprintln!("       qs-google-auth provision-all [--client-json PATH]");
    eprintln!("       qs-google-auth list-calendars --account ID");
}

fn parse_flags(
    args: &[String],
    needs_client: bool,
    needs_account: bool,
) -> Result<Options, String> {
    let mut opts = Options {
        account_id: String::new(),
        config_path: app_config::default_path(),
        client_json: String::new(),
    };

    let mut index = 0;
    while index < args.len() {
        match args[index].as_str() {
            "--account" => {
                index += 1;
                opts.account_id = require_value(args, index, "--account")?.to_owned();
            }
            "--config" => {
                index += 1;
                opts.config_path = PathBuf::from(require_value(args, index, "--config")?);
            }
            "--client-json" => {
                index += 1;
                opts.client_json = require_value(args, index, "--client-json")?.to_owned();
            }
            value => return Err(format!("unknown flag {value:?}")),
        }
        index += 1;
    }

    if needs_account && opts.account_id.trim().is_empty() {
        return Err("--account is required".to_owned());
    }
    if needs_client && opts.client_json.trim().is_empty() {
        return Err("--client-json is required".to_owned());
    }
    Ok(opts)
}

fn optional_path(value: &str) -> Option<&str> {
    let value = value.trim();
    (!value.is_empty()).then_some(value)
}

fn require_value<'a>(args: &'a [String], index: usize, flag: &str) -> Result<&'a str, String> {
    args.get(index)
        .map(String::as_str)
        .filter(|value| !value.starts_with("--"))
        .ok_or_else(|| format!("{flag} requires a value"))
}
