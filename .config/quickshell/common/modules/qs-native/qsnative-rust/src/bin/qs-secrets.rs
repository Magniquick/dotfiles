use std::env;
use std::io::{self, Read};
use std::process::ExitCode;

use qsnative_rust::secrets;

fn main() -> ExitCode {
    let args = env::args().skip(1).collect::<Vec<_>>();
    let Some(command) = args.first() else {
        usage();
        return ExitCode::from(2);
    };

    let result = match command.as_str() {
        "set" => set(&args[1..]),
        "check" => check(&args[1..]),
        "delete" => delete_keys(&args[1..]),
        _ => {
            usage();
            return ExitCode::from(2);
        }
    };

    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("{error}");
            ExitCode::from(1)
        }
    }
}

fn usage() {
    eprintln!("usage: qs-secrets set KEY < value");
    eprintln!("       qs-secrets check KEY...");
    eprintln!("       qs-secrets delete KEY...");
}

fn set(args: &[String]) -> Result<(), String> {
    if args.len() != 1 {
        return Err("set requires exactly one key".to_owned());
    }

    let key =
        secrets::normalize_key(&args[0]).ok_or_else(|| "secret key is required".to_owned())?;
    let mut value = String::new();
    io::stdin()
        .read_to_string(&mut value)
        .map_err(|error| error.to_string())?;
    let value = value.trim_end_matches(['\r', '\n']);

    secrets::set(&key, value).map_err(|error| error.to_string())?;
    println!("stored {key}");
    Ok(())
}

fn check(args: &[String]) -> Result<(), String> {
    if args.is_empty() {
        return Err("check requires at least one key".to_owned());
    }

    let mut missing = false;
    for key in args {
        if secrets::lookup(key).is_some() {
            println!("present {key}");
        } else {
            println!("missing {key}");
            missing = true;
        }
    }

    if missing {
        Err("one or more keys are missing".to_owned())
    } else {
        Ok(())
    }
}

fn delete_keys(args: &[String]) -> Result<(), String> {
    if args.is_empty() {
        return Err("delete requires at least one key".to_owned());
    }

    for key in args {
        secrets::delete(key).map_err(|error| error.to_string())?;
        println!("deleted {key}");
    }

    Ok(())
}
