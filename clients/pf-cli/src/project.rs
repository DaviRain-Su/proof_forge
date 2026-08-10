//! Project layout: `pf.toml` + default target/output resolution (cargo-like).
//!
//! External projects do **not** `lake require` ProofForge. The real dependency is
//! the installed compiler binary (`proof-forge-next`) plus the ProgramV1 source
//! gate (`import ProofForgeV2` is a text marker, not a Lake import). See
//! docs/product/02-external-program-v1.md and ADR-0037.

use crate::error::{PfError, PfResult};
use serde::Deserialize;
use std::fs;
use std::path::{Path, PathBuf};

pub const DEFAULT_TARGET: &str = "aleo";
pub const CONFIG_NAME: &str = "pf.toml";
pub const DEFAULT_COMPILER_DEP: &str = "proof-forge-next";
pub const DEFAULT_LANGUAGE_DEP: &str = "ProofForgeV2";

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub struct ProjectConfig {
    pub package: PackageSection,
    /// Required toolchain / product dependency (like Cargo.toml [dependencies]).
    #[serde(default)]
    pub dependencies: DependenciesSection,
    #[serde(default)]
    pub toolchain: ToolchainSection,
    #[serde(default)]
    pub build: BuildSection,
    #[serde(default)]
    pub network: NetworkSection,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub struct PackageSection {
    pub name: String,
    /// Lean module identity for proof-forge-next `--module`.
    pub module: String,
    /// Source path relative to project root.
    #[serde(default = "default_source")]
    pub source: String,
}

fn default_source() -> String {
    "src/Main.lean".into()
}

/// Product dependencies. Not crates.io — these name ProofForge surfaces.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub struct DependenciesSection {
    /// Compiler CLI product id (must be proof-forge-next for v0).
    #[serde(default = "default_compiler_dep")]
    pub compiler: String,
    /// Language/source-gate id expected in source (`import ProofForgeV2`).
    #[serde(default = "default_language_dep")]
    pub language: String,
}

impl Default for DependenciesSection {
    fn default() -> Self {
        Self {
            compiler: default_compiler_dep(),
            language: default_language_dep(),
        }
    }
}

fn default_compiler_dep() -> String {
    DEFAULT_COMPILER_DEP.into()
}

fn default_language_dep() -> String {
    DEFAULT_LANGUAGE_DEP.into()
}

/// How to find the compiler binary (Cargo-edition analogue of rust-toolchain).
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub struct ToolchainSection {
    /// Channel / product line (documentation + future pin).
    #[serde(default = "default_channel")]
    pub channel: String,
    /// Optional absolute path to proof-forge-next (else PROOF_FORGE_CLI / discovery).
    #[serde(default)]
    pub compiler_path: Option<String>,
    /// Optional path to monorepo/install root (PROOF_FORGE_ROOT).
    #[serde(default)]
    pub root: Option<String>,
}

impl Default for ToolchainSection {
    fn default() -> Self {
        Self {
            channel: default_channel(),
            compiler_path: None,
            root: None,
        }
    }
}

fn default_channel() -> String {
    "stable".into()
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub struct BuildSection {
    #[serde(default = "default_target_string")]
    pub default_target: String,
    /// Output root; final dir is `{out-dir}/{target}/`.
    #[serde(default = "default_out_dir")]
    pub out_dir: String,
}

impl Default for BuildSection {
    fn default() -> Self {
        Self {
            default_target: default_target_string(),
            out_dir: default_out_dir(),
        }
    }
}

fn default_target_string() -> String {
    DEFAULT_TARGET.into()
}

fn default_out_dir() -> String {
    "build".into()
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub struct NetworkSection {
    #[serde(default = "default_network")]
    pub default: String,
}

impl Default for NetworkSection {
    fn default() -> Self {
        Self {
            default: default_network(),
        }
    }
}

fn default_network() -> String {
    "testnet".into()
}

#[derive(Debug, Clone)]
pub struct Project {
    pub root: PathBuf,
    pub config: Option<ProjectConfig>,
}

impl Project {
    /// Walk cwd and parents for `pf.toml`. Always returns a Project (cwd if none).
    pub fn discover() -> PfResult<Self> {
        let cwd = std::env::current_dir()?;
        let mut dir = cwd.clone();
        loop {
            let cand = dir.join(CONFIG_NAME);
            if cand.is_file() {
                let cfg = load_config(&cand)?;
                return Ok(Self {
                    root: dir,
                    config: Some(cfg),
                });
            }
            if !dir.pop() {
                break;
            }
        }
        Ok(Self {
            root: cwd,
            config: None,
        })
    }

    pub fn require_config(&self) -> PfResult<&ProjectConfig> {
        self.config.as_ref().ok_or_else(|| {
            PfError::Usage(format!(
                "no {CONFIG_NAME} found (run `pf new <name>` or pass explicit source/--module)"
            ))
        })
    }

    /// Validate dependency declarations and apply toolchain env hints.
    pub fn apply_toolchain_env(&self) -> PfResult<()> {
        let Some(cfg) = &self.config else {
            return Ok(());
        };
        if cfg.dependencies.compiler != DEFAULT_COMPILER_DEP {
            return Err(PfError::Usage(format!(
                "[dependencies].compiler must be '{DEFAULT_COMPILER_DEP}' in pf v0 (got '{}')",
                cfg.dependencies.compiler
            )));
        }
        if cfg.dependencies.language != DEFAULT_LANGUAGE_DEP {
            return Err(PfError::Usage(format!(
                "[dependencies].language must be '{DEFAULT_LANGUAGE_DEP}' in pf v0 (got '{}')",
                cfg.dependencies.language
            )));
        }
        // Prefer config paths only when env not already set (env wins for CI).
        if std::env::var_os("PROOF_FORGE_CLI").is_none() {
            if let Some(p) = cfg.toolchain.compiler_path.as_ref() {
                if !p.is_empty() {
                    let path = expand_path(p);
                    std::env::set_var("PROOF_FORGE_CLI", &path);
                }
            }
        }
        if std::env::var_os("PROOF_FORGE_ROOT").is_none() {
            if let Some(p) = cfg.toolchain.root.as_ref() {
                if !p.is_empty() {
                    let path = expand_path(p);
                    std::env::set_var("PROOF_FORGE_ROOT", &path);
                }
            }
        }
        Ok(())
    }

    pub fn resolve_target(&self, cli_target: Option<&str>) -> String {
        if let Some(t) = cli_target {
            if !t.is_empty() {
                return t.to_string();
            }
        }
        if let Ok(t) = std::env::var("PF_TARGET") {
            if !t.is_empty() {
                return t;
            }
        }
        self.config
            .as_ref()
            .map(|c| c.build.default_target.clone())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| DEFAULT_TARGET.into())
    }

    pub fn resolve_network(&self, cli_network: Option<&str>) -> String {
        if let Some(n) = cli_network {
            if !n.is_empty() {
                return n.to_string();
            }
        }
        if let Ok(n) = std::env::var("PF_NETWORK") {
            if !n.is_empty() {
                return n;
            }
        }
        self.config
            .as_ref()
            .map(|c| c.network.default.clone())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| "testnet".into())
    }

    /// Default artifact directory: `{root}/{out_dir}/{target}/`
    pub fn default_artifact_dir(&self, target: &str) -> PathBuf {
        let out_root = self
            .config
            .as_ref()
            .map(|c| c.build.out_dir.as_str())
            .filter(|s| !s.is_empty())
            .unwrap_or("build");
        self.root.join(out_root).join(target)
    }

    /// Configured output root, constrained to remain beneath the project root.
    pub fn output_root(&self) -> PfResult<PathBuf> {
        let configured = self
            .config
            .as_ref()
            .map(|c| c.build.out_dir.as_str())
            .filter(|s| !s.is_empty())
            .unwrap_or("build");
        let relative = Path::new(configured);
        let safe = !relative.is_absolute()
            && relative.components().all(|component| {
                matches!(
                    component,
                    std::path::Component::Normal(_) | std::path::Component::CurDir
                )
            })
            && relative
                .components()
                .any(|c| matches!(c, std::path::Component::Normal(_)));
        if !safe {
            return Err(PfError::Safety(format!(
                "[build].out-dir must name a directory under the project root (got '{configured}')"
            )));
        }
        Ok(self.root.join(relative))
    }

    pub fn resolve_artifact_dir(
        &self,
        target: &str,
        cli_artifact: Option<&Path>,
        cli_output: Option<&Path>,
    ) -> PathBuf {
        if let Some(p) = cli_artifact {
            return absolutize(&self.root, p);
        }
        if let Some(p) = cli_output {
            return absolutize(&self.root, p);
        }
        self.default_artifact_dir(target)
    }

    pub fn resolve_source_module(
        &self,
        cli_source: Option<&Path>,
        cli_module: Option<&str>,
    ) -> PfResult<(PathBuf, String, Option<PathBuf>)> {
        if let (Some(src), Some(module)) = (cli_source, cli_module) {
            let src = absolutize(&self.root, src);
            let root = Some(self.root.clone());
            return Ok((src, module.to_string(), root));
        }

        let cfg = self.require_config()?;
        let src_rel = if let Some(s) = cli_source {
            s.to_path_buf()
        } else {
            PathBuf::from(&cfg.package.source)
        };
        let src = self.root.join(&src_rel);
        if !src.is_file() {
            return Err(PfError::Usage(format!(
                "source not found: {} (from {CONFIG_NAME})",
                src.display()
            )));
        }
        // Source-gate honesty: language dependency must appear as import marker.
        let text = fs::read_to_string(&src)?;
        let lang = &cfg.dependencies.language;
        let marker = format!("import {lang}");
        if !text.contains(&marker) {
            return Err(PfError::Usage(format!(
                "{} must contain exact `{marker}` (product source gate; not a Lake package import)",
                src.display()
            )));
        }
        let module = cli_module
            .map(|s| s.to_string())
            .unwrap_or_else(|| cfg.package.module.clone());
        Ok((src, module, Some(self.root.clone())))
    }
}

pub fn load_config(path: &Path) -> PfResult<ProjectConfig> {
    let text = fs::read_to_string(path)?;
    toml::from_str(&text).map_err(|e| PfError::Usage(format!("invalid {}: {e}", path.display())))
}

pub fn write_new_project(dir: &Path, name: &str, target: &str) -> PfResult<()> {
    if dir.exists() {
        return Err(PfError::Usage(format!(
            "destination already exists: {}",
            dir.display()
        )));
    }
    validate_package_name(name)?;
    let module = to_module_name(name);
    let program = module.clone();

    fs::create_dir_all(dir.join("src"))?;
    let cfg = format!(
        r#"# ProofForge project manifest (developer CLI `pf`)
# Spec: docs/specs/cli-developer.md · External guide: docs/product/02-external-program-v1.md
#
# This is NOT a Lake package and does NOT `require` ProofForge as a Lean library.
# Your real dependency is the installed compiler binary + ProgramV1 language gate:
#   [dependencies] compiler = "proof-forge-next"   # CLI product
#   [dependencies] language = "ProofForgeV2"       # source must contain: import ProofForgeV2
# Point toolchain.compiler-path or set PROOF_FORGE_CLI to the binary.

[package]
name = "{name}"
module = "{module}"
source = "src/{module}.lean"

[dependencies]
# Product compiler (spawned by `pf build`). Not crates.io / not lake-packages.
compiler = "proof-forge-next"
# Language surface / source-gate id (text marker in .lean, not Lake import resolution).
language = "ProofForgeV2"

[toolchain]
channel = "stable"
# compiler-path = "/absolute/path/to/proof-forge-next"
# root = "/absolute/path/to/proof_forge"   # optional PROOF_FORGE_ROOT

[build]
default-target = "{target}"
out-dir = "build"

[network]
default = "testnet"
"#
    );
    fs::write(dir.join(CONFIG_NAME), cfg)?;

    let lean = format!(
        r#"import ProofForgeV2

-- External ProgramV1 template (StateCell-shaped).
-- The line above is a *product source gate*, not a Lake package import.
-- Build with the installed compiler: `pf build` → proof-forge-next.

open ProofForgeV2.Language

program {program} where
  state count : UInt64

  init(initial : UInt64) do
    count := initial

  entry increment(delta : UInt64) : UInt64 do
    count := count + delta
    return count

  view get() : UInt64 do
    return count
"#
    );
    fs::write(dir.join("src").join(format!("{module}.lean")), lean)?;

    fs::write(
        dir.join(".gitignore"),
        "build/\nout-*/\n.pf/\n*.deployment.json\n*.execution.json\n",
    )?;

    fs::write(
        dir.join("README.md"),
        format!(
            r#"# {name}

ProofForge **external ProgramV1** project (default target: **{target}**).

## Dependency model (read this)

Unlike Cargo/`lake`, this project does **not** vendor Lean libraries via
`[dependencies]` crate paths. Build is:

```text
pf  →  proof-forge-next (compiler binary)  →  reads src/*.lean  →  chain artifacts
```

| What you depend on | How it is declared |
|---|---|
| Compiler product | `[dependencies] compiler = "proof-forge-next"` + `PROOF_FORGE_CLI` or `[toolchain].compiler-path` |
| Language / DSL gate | `[dependencies] language = "ProofForgeV2"` + source line `import ProofForgeV2` |
| Optional host tools (Aleo) | Leo on host / Tool Root — not a Lean package |

Python `proof-forge-sdk` is an optional **host** client for agents/scripts; it is
**not** required inside this contract project.

## Quick start

```bash
export PROOF_FORGE_CLI=/path/to/proof-forge-next   # or set toolchain.compiler-path

pf build                 # → build/{target}/  (reads pf.toml; no long paths)
```

Then, by target:

| default-target | next |
|---|---|
| `aleo` | `pf run -- initialize 5u64` · `pf deploy` (save-only) |
| `solana` | `pf test` (local Mollusk, StateCell-shaped) |
| `evm` | `pf test` (local Anvil) |

Override target once: `pf build -t solana` (still short; no `--module` needed inside a project).
"#
        ),
    )?;
    Ok(())
}

fn expand_path(p: &str) -> String {
    if let Some(rest) = p.strip_prefix("~/") {
        if let Ok(home) = std::env::var("HOME") {
            return format!("{home}/{rest}");
        }
    }
    p.to_string()
}

fn validate_package_name(name: &str) -> PfResult<()> {
    if name.is_empty() {
        return Err(PfError::Usage("package name is empty".into()));
    }
    let ok = name
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-');
    if !ok || name.starts_with('-') {
        return Err(PfError::Usage(format!(
            "invalid package name '{name}' (use [A-Za-z0-9_-]+)"
        )));
    }
    Ok(())
}

fn to_module_name(name: &str) -> String {
    let mut out = String::new();
    let mut cap = true;
    for c in name.chars() {
        if c == '-' || c == '_' {
            cap = true;
            continue;
        }
        if cap {
            out.extend(c.to_uppercase());
            cap = false;
        } else {
            out.push(c);
        }
    }
    if out.is_empty() {
        "Main".into()
    } else {
        out
    }
}

fn absolutize(root: &Path, p: &Path) -> PathBuf {
    if p.is_absolute() {
        p.to_path_buf()
    } else {
        root.join(p)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn module_name() {
        assert_eq!(to_module_name("hello"), "Hello");
        assert_eq!(to_module_name("hello-world"), "HelloWorld");
    }

    #[test]
    fn parse_minimal_toml_defaults_deps() {
        let t = r#"
[package]
name = "demo"
module = "Demo"
source = "src/Demo.lean"
"#;
        let c: ProjectConfig = toml::from_str(t).unwrap();
        assert_eq!(c.package.name, "demo");
        assert_eq!(c.build.default_target, "aleo");
        assert_eq!(c.dependencies.compiler, "proof-forge-next");
        assert_eq!(c.dependencies.language, "ProofForgeV2");
    }

    #[test]
    fn parse_full_deps() {
        let t = r#"
[package]
name = "demo"
module = "Demo"

[dependencies]
compiler = "proof-forge-next"
language = "ProofForgeV2"

[toolchain]
channel = "stable"
compiler-path = "/opt/pf/proof-forge-next"
"#;
        let c: ProjectConfig = toml::from_str(t).unwrap();
        assert_eq!(
            c.toolchain.compiler_path.as_deref(),
            Some("/opt/pf/proof-forge-next")
        );
    }

    #[test]
    fn output_root_rejects_paths_outside_project() {
        let config: ProjectConfig = toml::from_str(
            r#"
[package]
name = "demo"
module = "Demo"
[build]
out-dir = "../outside"
"#,
        )
        .unwrap();
        let project = Project {
            root: PathBuf::from("/tmp/demo"),
            config: Some(config),
        };
        assert!(matches!(project.output_root(), Err(PfError::Safety(_))));
    }
}
