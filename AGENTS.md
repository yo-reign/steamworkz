# Steamworkz agent instructions

## Source and distribution

- Target Zig 0.16.0 and the user-supplied official Steamworks SDK 1.65.
- Never copy SDK headers, libraries, archives, runtime binaries, or SDK directories into versioned source or package archives.
- Use an external `-Dsdk` option or `STEAMWORKS_SDK`. Do not download the SDK or commit machine-specific paths.
- Keep SDK adaptation in the private C/C++ bridge compiled by Zig. Public game code must use Zig APIs only.
- Compile against official headers. Do not guess SDK layouts/vtables or copy another binding's source.
- Do not introduce JavaScript, Node, Bun, binding-generation scripts, or C++ standard-library dependencies.

## API and tests

- Prefer concrete types, `const`, and `*const T` when mutation is unnecessary.
- Keep declarations private unless cross-module production use or a required callback/entry-point contract needs them.
- Test private helpers in their owning source files. Do not expose test-only wrappers.
- Preserve explicit allocation, stable client storage, owner-thread/session checks in release builds, and unknown native enum values.
- Separate native acceptance from asynchronous completion and operation success.
- Document borrowed versus owned memory and every resource's teardown rule.
- Test meaningful behavior, failures, and lifecycle rules, not incidental tuning constants.
- Offline tests must not initialize Steam or perform account, network-service, persistent-file, social, or purchase actions.
- Live tests require explicit bounded authority. Do not log ticket bytes or secrets.

## Coordination

- Read ROADMAP.md and CHECKPOINT.md before work. Their current authority and lane ownership apply.
- The approved implementation batch waives individual patch approval only for that documented scope.
- One writer owns each checkout/worktree. Use isolated worktrees for concurrent writers.
- Children may edit only their assigned files/contracts. They may not stage, commit, push, publish, run live checks, or delegate unless explicitly assigned that authority.
- The parent owns integration, acceptance, shared progress records, and publication.
- Separate approval is required for unrelated work. Do not commit or push the consuming game.
- The user creates the remote repository and provides its push URL. Do not create it for them.
- Keep scratch logs and agent reports outside source. Retain recovery worktrees unless cleanup is authorized.
- Report failed, skipped, blocked, and unexecuted checks accurately. Compile/link success is not runtime validation.

## Commits

Use lightweight Conventional Commits with lowercase types and an imperative summary.
Prefer one logical change with supporting tests/docs. Keep the summary within 72 characters.
Do not commit or publish a partial implementation as accepted production-ready work.
