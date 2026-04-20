mod model;
mod noise;
mod render;
mod signature;

use std::env;
use std::fs;
use std::path::PathBuf;

use anyhow::{anyhow, Context, Result};

use crate::model::{default_request, AppRequest, RenderMode};
use crate::render::run_request;

fn main() {
    if let Err(error) = try_main() {
        eprintln!("{error:#}");
        std::process::exit(1);
    }
}

fn try_main() -> Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() == 2 && args[1] == "--print-default-request" {
        println!("{}", serde_json::to_string_pretty(&default_request())?);
        return Ok(());
    }

    let cli = parse_args(&args)?;
    let request_bytes = fs::read(&cli.request_path)
        .with_context(|| format!("failed to read request: {}", cli.request_path.display()))?;
    let request: AppRequest = serde_json::from_slice(&request_bytes)
        .with_context(|| format!("invalid request json: {}", cli.request_path.display()))?;
    let request = request.sanitized();

    let manifest = run_request(cli.mode, request, &cli.output_dir)?;
    let manifest_path = cli.output_dir.join("manifest.json");
    fs::write(&manifest_path, serde_json::to_vec_pretty(&manifest)?)
        .with_context(|| format!("failed to write manifest: {}", manifest_path.display()))?;
    println!("{}", serde_json::to_string_pretty(&manifest)?);
    Ok(())
}

struct Cli {
    mode: RenderMode,
    request_path: PathBuf,
    output_dir: PathBuf,
}

fn parse_args(args: &[String]) -> Result<Cli> {
    let mut mode = RenderMode::Full;
    let mut request_path: Option<PathBuf> = None;
    let mut output_dir: Option<PathBuf> = None;
    let mut index = 1;

    while index < args.len() {
        match args[index].as_str() {
            "--mode" => {
                index += 1;
                let value = args.get(index).ok_or_else(|| anyhow!("missing value for --mode"))?;
                mode = RenderMode::from_arg(value);
            }
            "--request" => {
                index += 1;
                let value = args.get(index).ok_or_else(|| anyhow!("missing value for --request"))?;
                request_path = Some(PathBuf::from(value));
            }
            "--output" => {
                index += 1;
                let value = args.get(index).ok_or_else(|| anyhow!("missing value for --output"))?;
                output_dir = Some(PathBuf::from(value));
            }
            unknown => {
                return Err(anyhow!(
                    "unknown argument: {unknown}. expected --mode <draft|full> --request <json> --output <dir>"
                ));
            }
        }
        index += 1;
    }

    Ok(Cli {
        mode,
        request_path: request_path.ok_or_else(|| anyhow!("--request is required"))?,
        output_dir: output_dir.ok_or_else(|| anyhow!("--output is required"))?,
    })
}
