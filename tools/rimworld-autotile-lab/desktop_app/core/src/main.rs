mod model;
mod decal;
mod noise;
mod render;
mod silhouette;
mod signature;

use std::env;
use std::fs;
use std::path::PathBuf;

use anyhow::{anyhow, Context, Result};

use crate::model::{default_request, AppRequest, RenderMode};

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

    let manifest = match cli.mode {
        CliMode::Terrain(render_mode) => {
            serde_json::to_value(render::run_request(render_mode, request, &cli.output_dir)?)?
        }
        CliMode::Decals => serde_json::to_value(decal::run_request(&request, &cli.output_dir)?)?,
        CliMode::Silhouettes => serde_json::to_value(silhouette::run_request(&request, &cli.output_dir)?)?,
    };
    let manifest_path = cli.output_dir.join("manifest.json");
    fs::write(&manifest_path, serde_json::to_vec_pretty(&manifest)?)
        .with_context(|| format!("failed to write manifest: {}", manifest_path.display()))?;
    println!("{}", serde_json::to_string_pretty(&manifest)?);
    Ok(())
}

struct Cli {
    mode: CliMode,
    request_path: PathBuf,
    output_dir: PathBuf,
}

enum CliMode {
    Terrain(RenderMode),
    Decals,
    Silhouettes,
}

fn parse_args(args: &[String]) -> Result<Cli> {
    let mut mode = CliMode::Terrain(RenderMode::Full);
    let mut request_path: Option<PathBuf> = None;
    let mut output_dir: Option<PathBuf> = None;
    let mut index = 1;

    while index < args.len() {
        match args[index].as_str() {
            "--mode" => {
                index += 1;
                let value = args.get(index).ok_or_else(|| anyhow!("missing value for --mode"))?;
                mode = parse_mode(value);
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
                    "unknown argument: {unknown}. expected --mode <draft|full|decals|silhouettes> --request <json> --output <dir>"
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

fn parse_mode(value: &str) -> CliMode {
    match value.trim().to_ascii_lowercase().as_str() {
        "decal" | "decals" => CliMode::Decals,
        "silhouette" | "silhouettes" => CliMode::Silhouettes,
        _ => CliMode::Terrain(RenderMode::from_arg(value)),
    }
}
