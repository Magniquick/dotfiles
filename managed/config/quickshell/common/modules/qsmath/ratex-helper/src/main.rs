use std::io::{self, BufRead};
use std::path::PathBuf;

use ratex_layout::{layout, to_display_list, LayoutOptions};
use ratex_parser::parser::parse;
use ratex_svg::{render_to_svg, SvgOptions};
use ratex_types::color::Color;
use ratex_types::math_style::MathStyle;

fn main() {
    let args: Vec<String> = std::env::args().collect();

    let output_dir = arg_value(&args, "--output-dir").unwrap_or_else(|| "output_svg".to_string());
    let dpr = arg_value(&args, "--dpr")
        .and_then(|value| value.parse::<f64>().ok())
        .unwrap_or(1.0)
        .clamp(0.01, 16.0);
    let font_size = arg_value(&args, "--font-size")
        .and_then(|value| value.parse::<f64>().ok())
        .unwrap_or(40.0);
    let padding = arg_value(&args, "--padding")
        .and_then(|value| value.parse::<f64>().ok())
        .unwrap_or(0.0);
    let color = arg_value(&args, "--color")
        .map(|value| parse_color_arg(&value))
        .transpose()
        .unwrap_or_else(|message| {
            eprintln!("ERR {message}");
            std::process::exit(2);
        })
        .unwrap_or(Color::BLACK);
    let font_dir = arg_value(&args, "--font-dir").unwrap_or_else(default_font_dir);

    std::fs::create_dir_all(&output_dir).expect("Failed to create output dir");

    let svg_opts = SvgOptions {
        font_size: font_size * dpr,
        padding: padding * dpr,
        stroke_width: 1.5 * dpr,
        embed_glyphs: true,
        font_dir,
    };

    let style = if args.iter().any(|arg| arg == "--inline") {
        MathStyle::Text
    } else {
        MathStyle::Display
    };
    let layout_opts = LayoutOptions::default().with_style(style).with_color(color);

    let mut count = 0;
    for line in io::stdin().lock().lines() {
        let line = line.expect("Failed to read line");
        let expr = line.trim();
        if expr.is_empty() || expr.starts_with('#') {
            continue;
        }

        count += 1;
        match svg_formula(expr, &layout_opts, &svg_opts) {
            Ok(svg) => {
                let path = PathBuf::from(&output_dir).join(format!("{count:04}.svg"));
                std::fs::write(&path, svg.as_bytes()).expect("Failed to write SVG");
                println!("OK  {count:4} {expr}");
            }
            Err(error) => {
                eprintln!("ERR {count:4} {expr} - {error}");
            }
        }
    }
}

fn arg_value(args: &[String], name: &str) -> Option<String> {
    args.iter()
        .position(|arg| arg == name)
        .and_then(|index| args.get(index + 1))
        .cloned()
}

fn svg_formula(
    expr: &str,
    layout_opts: &LayoutOptions,
    svg_opts: &SvgOptions,
) -> Result<String, String> {
    let ast = parse(expr).map_err(|error| format!("Parse error: {error}"))?;
    let layout_box = layout(&ast, layout_opts);
    let display_list = to_display_list(&layout_box);
    Ok(render_to_svg(&display_list, svg_opts))
}

fn default_font_dir() -> String {
    "fonts".to_string()
}

fn parse_color_arg(value: &str) -> Result<Color, String> {
    Color::parse(value).ok_or_else(|| {
        format!("invalid --color '{value}': expected a named color, #rgb, #rrggbb, or [MODEL]value")
    })
}
