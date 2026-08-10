//! Project layout: `pf.toml` + default target/output resolution (cargo-like).

use crate::error::{PfError, PfResult};
use serde::Deserialize;
use std::fs;
use std::path::{Path, PathBuf};

pub const DEFAULT_TARGET: &str = "aleo";
pub const CONFIG_NAME: &str = "pf.toml";

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub struct ProjectConfig {
    pub package: PackageSection,
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
            // If user passes bare -o build/foo, respect it; if they pass a root without target,
            // we still use as-is (explicit wins).
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
        let module = cli_module
            .map(|s| s.to_string())
            .unwrap_or_else(|| cfg.package.module.clone());
        Ok((src, module, Some(self.root.clone())))
    }
}

pub fn load_config(path: &Path) -> PfResult<ProjectConfig> {
    let text = fs::read_to_string(path)?;
    // Minimal TOML subset via toml crate — add dependency.
    toml::from_str(&text).map_err(|e| {
        PfError::Usage(format!("invalid {}: {e}", path.display()))
    })
}

pub fn write_new_project(dir: &Path, name: &str, target: &str) -> PfResult<()> {
    if dir.exists() {
        return Err(PfError::Usage(format!(
            "destination already exists: {}",
            dir.display()
        )));
    }
    validate_package_name(name)?;
    // Module = name with first char uppercased for Lean convention when possible.
    let module = to_module_name(name);
    let program = module.clone();

    fs::create_dir_all(dir.join("src"))?;
    let cfg = format!(
        r#"# ProofForge project (developer CLI `pf`)
# See docs/specs/cli-developer.md

[package]
name = "{name}"
module = "{module}"
source = "src/{module}.lean"

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
-- Build: `pf build`   Local: `pf run -- initialize 5u64`

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

ProofForge program (default target: **{target}**).

```bash
export PROOF_FORGE_CLI=/path/to/proof-forge-next

pf build                 # → build/{target}/
pf run -- initialize 5u64
pf run -- increment 3u64
pf deploy --network testnet   # save-only by default
```

Config: `pf.toml`. Override target: `pf build --target solana` or `PF_TARGET=evm pf build`.
"#
        ),
    )?;
    Ok(())
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
    // Hello-world → HelloWorld; hello → Hello
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
    fn parse_minimal_toml() {
        let t = r#"
[package]
name = "demo"
module = "Demo"
source = "src/Demo.lean"
"#;
        let c: ProjectConfig = toml::from_str(t).unwrap();
        assert_eq!(c.package.name, "demo");
        assert_eq!(c.build.default_target, "aleo");
        assert_eq!(c.build.out_dir, "build");
    }
}
