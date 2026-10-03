# ADR 0022: Scope predictive back to the visible tab

Status: Accepted for T-167j implementation; physical Android verification pending

## Context

The Home shell keeps one nested Navigator per tab. Flutter's Android predictive
transition builder registers a binding observer for each current page route.
The binding dispatches one system gesture to every accepting observer, so
retained offstage tab routes can all respond to a single gesture unless their
predictive transition is disabled. A root sheet or dialog also covers the tab
shell and must own back before any nested route.

## Decision

- Keep each tab Navigator and its route stack alive across tab switches and
  PageView swipes.
- Use the app's existing Android page-transition builder only for the active
  tab while the Home shell's root route is current. Retained inactive tabs and
  covered tabs use a non-gesture Android transition. Preserve every non-Android
  builder and any app-selected Android builder that is not Flutter's standard
  predictive builder.
- A root modal owns back before HomeShell. A committed predictive gesture on a
  nested page pops exactly that active page; cancel leaves every stack and the
  Home exit confirmation unchanged. A root dialog that has no predictive route
  transition uses the normal committed-back fallback and closes only itself.
- Ordinary shell back asks the active Navigator to `maybePop`, returns a
  non-Home tab root to Home, and never pops a route above Home. Home-root back
  announces a live-region prompt; only a second back within two seconds exits.
- Route, tab, root-overlay, visible-keyboard, and app-lifecycle changes clear a
  pending exit confirmation. Keyboard focus without a visible software
  keyboard does not consume back.

## Consequences

The shell must retain all tab pages and scope transition themes as active-tab
and root-route state changes. Dialogs continue to use framework back handling;
host widget tests can verify committed/canceled channel messages and route
ownership, but native predictive animation, launcher preview, and IME precedence
remain physical-device acceptance gates. No storage, SMS, permission, or
cross-platform transition contract changes.

Rollback: remove the shell-scoped transition selection and restore the prior
shell back handler. This would reintroduce the risk of multiple inactive tab
stacks responding to one Android predictive gesture.
