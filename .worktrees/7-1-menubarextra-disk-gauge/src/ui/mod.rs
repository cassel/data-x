pub mod colors;
mod details;
mod input;
mod layout;
pub mod stats;
mod tooltip;
mod tree_view;
mod treemap;

pub use colors::ColorScheme;
pub use input::{handle_key, Command, ConfirmAction, FileCategory, InputMode, SortBy, ViewMode};
pub use layout::{render_ui, BreadcrumbItem};
pub use stats::AggregatedStats;
pub use treemap::TreemapRect;

// Re-exported for potential future use by other agents
#[allow(unused_imports)]
pub use details::render_details_panel;
#[allow(unused_imports)]
pub use layout::format_size;
#[allow(unused_imports)]
pub use stats::{render_stats_panel, FileTypeStats, StatsCategory};
#[allow(unused_imports)]
pub use tooltip::render_tooltip;
#[allow(unused_imports)]
pub use tree_view::{render_tree_view, TreeViewState};
#[allow(unused_imports)]
pub use treemap::render_treemap;
