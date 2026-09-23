///|
/// Keep derived trait methods explicit for newer MoonBit toolchains.
pub extend ExecutionScript with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ExecutionScript with Eq::{not_equal, equal}

///|
pub extend ExecutionRecord with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ExecutionRecord with Eq::{not_equal, equal}

///|
pub extend ExecutionRun with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ExecutionRun with Eq::{not_equal, equal}

///|
pub extend InMemoryExecutor with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend InMemoryExecutor with Eq::{not_equal, equal}
