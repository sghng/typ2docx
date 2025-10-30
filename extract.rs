//! Example script to extract equation nodes from a Typst project.
//!
//! Usage:
//!   cargo run --example extract_equations -- main.typ
//!
//! This script demonstrates how to:
//! 1. Parse a Typst file into an AST
//! 2. Find all include/import statements and recursively process included files
//! 3. Recursively traverse the AST
//! 4. Find nodes with SyntaxKind::Equation
//! 5. Extract and print their source code

use std::collections::HashSet;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use typst_syntax::ast::{AstNode, Expr, ModuleInclude, ModuleImport};
use typst_syntax::{parse, SyntaxKind, SyntaxNode};

fn main() {
    let arg = env::args().nth(1).expect("Usage: extract_equations <path-to-typ-file>");
    let file_path = Path::new(&arg);

    let project_root = file_path.parent().unwrap_or(Path::new("."));
    let mut visited = HashSet::new();
    let mut equations = Vec::new();

    if let Err(e) = process_file(file_path, project_root, &mut visited, &mut equations) {
        eprintln!("Error: {}", e);
        std::process::exit(1);
    }

    if equations.is_empty() {
        println!("No equations found.");
    } else {
        println!("Found {} equation(s) in {} file(s):\n", equations.len(), visited.len());
        for (i, (file, eq)) in equations.iter().enumerate() {
            println!("Equation {} (from {}):\n{}\n", i + 1, file.display(), eq);
        }
    }
}

fn process_file(
    file_path: &Path,
    project_root: &Path,
    visited: &mut HashSet<PathBuf>,
    equations: &mut Vec<(PathBuf, String)>,
) -> Result<(), String> {
    let canonical = file_path.canonicalize()
        .map_err(|e| format!("Failed to read '{}': {}", file_path.display(), e))?;

    if !visited.insert(canonical.clone()) {
        return Ok(()); // Already visited
    }

    let content = fs::read_to_string(file_path)
        .map_err(|e| format!("Failed to read '{}': {}", file_path.display(), e))?;

    let root = parse(&content);
    traverse(&root, &canonical, file_path, project_root, visited, equations)?;

    Ok(())
}

fn traverse(
    node: &SyntaxNode,
    file_path: &PathBuf,
    current_file: &Path,
    project_root: &Path,
    visited: &mut HashSet<PathBuf>,
    equations: &mut Vec<(PathBuf, String)>,
) -> Result<(), String> {
    // Collect equations
    if node.kind() == SyntaxKind::Equation {
        equations.push((file_path.clone(), node.clone().into_text().to_string()));
    }

    // Process imports/includes
    if let Some(import) = ModuleImport::from_untyped(node) {
        if let Some(path) = get_path(&import.source()) {
            process_file(&resolve_path(&path, current_file, project_root)?, project_root, visited, equations)?;
        }
    } else if let Some(include) = ModuleInclude::from_untyped(node) {
        if let Some(path) = get_path(&include.source()) {
            process_file(&resolve_path(&path, current_file, project_root)?, project_root, visited, equations)?;
        }
    }

    // Recurse into children
    for child in node.children() {
        traverse(child, file_path, current_file, project_root, visited, equations)?;
    }

    Ok(())
}

fn get_path(expr: &Expr) -> Option<String> {
    match expr {
        Expr::Str(s) if !s.get().starts_with('@') => Some(s.get().to_string()),
        _ => None,
    }
}

fn resolve_path(path_str: &str, current_file: &Path, project_root: &Path) -> Result<PathBuf, String> {
    let path = if path_str.starts_with('/') {
        project_root.join(&path_str[1..])
    } else {
        current_file.parent()
            .ok_or_else(|| format!("Cannot resolve path from {}", current_file.display()))?
            .join(path_str)
    };

    let path = if path.extension().is_none() {
        path.with_extension("typ")
    } else {
        path
    };

    path.canonicalize().map_err(|_| format!("File not found: {}", path.display()))
}
