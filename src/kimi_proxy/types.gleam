//// Shared data types, kept in one leaf module so other modules can reference
//// them without forming import cycles — which spec §4 explicitly permits
//// ("create a types file or distribute types to owner modules"):
////
////  - Context types (`ContextBlock`, `AssembledContext`) so `tokens` and
////    `context` don't cycle (Phase 3).
////  - Routing types (`Intent`, `RouteMode`, `Turn`, `Task`) so `memory` and
////    `context` (which need `Task`) don't cycle with `router` (which needs
////    `memory`/`context` for orchestration). The only dependency is `provider`,
////    for `Role`.

import kimi_proxy/provider.{type Role}

/// A single labelled chunk of context with a priority and an estimated size.
/// `priority` 1 = most important (dropped last). Spec §4.4 / §6.4.
pub type ContextBlock {
  ContextBlock(label: String, content: String, priority: Int, est_tokens: Int)
}

/// The result of fitting blocks into a token budget.
pub type AssembledContext {
  AssembledContext(
    blocks: List(ContextBlock),
    total_tokens: Int,
    dropped: List(String),
  )
}

/// What the user is trying to do, decided by the rule-based classifier (§4.2).
pub type Intent {
  Planning
  Coding
  Question
}

/// How a request should be routed, derived from the OpenAI `model` field.
pub type RouteMode {
  Auto
  ForceRole(Role)
  DirectModel(String)
}

/// One conversation turn from the incoming request.
pub type Turn {
  Turn(role: String, content: String)
}

/// A unit of work assembled from an incoming request. `task_root` is the
/// absolute path of the oo7 task folder the client detected (walk-up to the
/// nearest TASK.md), or "" when the request carries none — the router injects
/// that folder's markdown files as live context when it is set.
pub type Task {
  Task(
    mode: RouteMode,
    intent: Intent,
    user_prompt: String,
    history: List(Turn),
    task_root: String,
  )
}
