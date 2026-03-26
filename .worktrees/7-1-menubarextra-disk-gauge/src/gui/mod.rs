//! GUI module for Data-X disk analyzer using egui/eframe.
//!
//! This module provides a native GUI interface as an alternative to the TUI.
//! It offers the same functionality with a more visual, mouse-driven interface.

#[cfg(feature = "gui")]
mod app;
#[cfg(feature = "gui")]
pub mod tree_panel;
#[cfg(feature = "gui")]
pub mod treemap_panel;

#[cfg(feature = "gui")]
pub use app::DataXApp;
#[cfg(feature = "gui")]
pub use tree_panel::{render_tree_panel, render_tree_panel_with_colors, TreePanelColors, TreePanelState};
#[cfg(feature = "gui")]
pub use treemap_panel::{FileTypeCategory, TreemapPanel, TreemapRect, TreemapResponse, TreemapState};
