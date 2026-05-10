mod decal;
mod model;
mod noise;
mod render;
mod sdf;
mod signature;
mod silhouette;

use std::env;
use std::fs;
use std::io::{self, BufRead, Write};
use std::path::PathBuf;

use anyhow::{Context, Result, anyhow};
use schemars::schema_for;
use serde::{Deserialize, Serialize};

use crate::model::{AppRequest, RenderMode, default_request};
use crate::render::RenderOptions;

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
    if args.len() == 2 && args[1] == "--print-request-schema" {
        println!(
            "{}",
            serde_json::to_string_pretty(&schema_for!(AppRequest))?
        );
        return Ok(());
    }
    if args.len() == 2 && args[1] == "--serve" {
        return serve_loop();
    }

    let cli = parse_args(&args)?;
    let request_bytes = fs::read(&cli.request_path)
        .with_context(|| format!("failed to read request: {}", cli.request_path.display()))?;
    let request: AppRequest = serde_json::from_slice(&request_bytes)
        .with_context(|| format!("invalid request json: {}", cli.request_path.display()))?;
    let request = request.sanitized();

    let manifest = match cli.mode {
        CliMode::Terrain(render_mode) => serde_json::to_value(render::run_request_with_options(
            render_mode,
            request,
            &cli.output_dir,
            RenderOptions {
                inline_preview: cli.inline_preview,
                transient: cli.transient,
            },
        )?)?,
        CliMode::Decals => serde_json::to_value(decal::run_request(&request, &cli.output_dir)?)?,
        CliMode::Silhouettes => {
            serde_json::to_value(silhouette::run_request(&request, &cli.output_dir)?)?
        }
    };
    if !cli.transient {
        let manifest_path = cli.output_dir.join("manifest.json");
        fs::write(&manifest_path, serde_json::to_vec_pretty(&manifest)?)
            .with_context(|| format!("failed to write manifest: {}", manifest_path.display()))?;
    }
    println!("{}", serde_json::to_string_pretty(&manifest)?);
    Ok(())
}

struct Cli {
    mode: CliMode,
    request_path: PathBuf,
    output_dir: PathBuf,
    inline_preview: bool,
    transient: bool,
}

enum CliMode {
    Terrain(RenderMode),
    Decals,
    Silhouettes,
}

#[derive(Deserialize)]
struct ServeRequest {
    id: u64,
    mode: String,
    request: AppRequest,
    output: PathBuf,
    #[serde(default)]
    inline_preview: bool,
    #[serde(default)]
    transient: bool,
}

#[derive(Serialize)]
struct ServeResponse {
    id: u64,
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    manifest: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

fn serve_loop() -> Result<()> {
    let stdin = io::stdin();
    let mut stdout = io::stdout();
    for line in stdin.lock().lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }
        let response = handle_serve_line(&line);
        writeln!(stdout, "{}", serde_json::to_string(&response)?)?;
        stdout.flush()?;
    }
    Ok(())
}

fn handle_serve_line(line: &str) -> ServeResponse {
    let parsed: Result<ServeRequest, _> = serde_json::from_str(line);
    match parsed {
        Ok(message) => {
            let id = message.id;
            let request = message.request.sanitized();
            let result = match parse_mode(&message.mode) {
                CliMode::Terrain(render_mode) => render::run_request_with_options(
                    render_mode,
                    request,
                    &message.output,
                    RenderOptions {
                        inline_preview: message.inline_preview,
                        transient: message.transient,
                    },
                )
                .and_then(|manifest| serde_json::to_value(manifest).map_err(Into::into)),
                CliMode::Decals => decal::run_request(&request, &message.output)
                    .and_then(|manifest| serde_json::to_value(manifest).map_err(Into::into)),
                CliMode::Silhouettes => silhouette::run_request(&request, &message.output)
                    .and_then(|manifest| serde_json::to_value(manifest).map_err(Into::into)),
            };
            match result {
                Ok(manifest) => ServeResponse {
                    id,
                    ok: true,
                    manifest: Some(manifest),
                    error: None,
                },
                Err(error) => ServeResponse {
                    id,
                    ok: false,
                    manifest: None,
                    error: Some(format!("{error:#}")),
                },
            }
        }
        Err(error) => ServeResponse {
            id: 0,
            ok: false,
            manifest: None,
            error: Some(format!("invalid server request: {error}")),
        },
    }
}

fn parse_args(args: &[String]) -> Result<Cli> {
    let mut mode = CliMode::Terrain(RenderMode::Full);
    let mut request_path: Option<PathBuf> = None;
    let mut output_dir: Option<PathBuf> = None;
    let mut inline_preview = false;
    let mut transient = false;
    let mut index = 1;

    while index < args.len() {
        match args[index].as_str() {
            "--mode" => {
                index += 1;
                let value = args
                    .get(index)
                    .ok_or_else(|| anyhow!("missing value for --mode"))?;
                mode = parse_mode(value);
            }
            "--request" => {
                index += 1;
                let value = args
                    .get(index)
                    .ok_or_else(|| anyhow!("missing value for --request"))?;
                request_path = Some(PathBuf::from(value));
            }
            "--output" => {
                index += 1;
                let value = args
                    .get(index)
                    .ok_or_else(|| anyhow!("missing value for --output"))?;
                output_dir = Some(PathBuf::from(value));
            }
            "--inline-preview" => {
                inline_preview = true;
            }
            "--transient" => {
                transient = true;
            }
            unknown => {
                return Err(anyhow!(
                    "unknown argument: {unknown}. expected --mode <draft|full|decals|silhouettes> --request <json> --output <dir> [--inline-preview] [--transient]"
                ));
            }
        }
        index += 1;
    }

    Ok(Cli {
        mode,
        request_path: request_path.ok_or_else(|| anyhow!("--request is required"))?,
        output_dir: output_dir.ok_or_else(|| anyhow!("--output is required"))?,
        inline_preview,
        transient,
    })
}

fn parse_mode(value: &str) -> CliMode {
    match value.trim().to_ascii_lowercase().as_str() {
        "decal" | "decals" => CliMode::Decals,
        "silhouette" | "silhouettes" => CliMode::Silhouettes,
        _ => CliMode::Terrain(RenderMode::from_arg(value)),
    }
}
