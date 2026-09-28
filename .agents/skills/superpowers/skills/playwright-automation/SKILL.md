# Playwright Automation Flow

## Goal
Establish a robust, repeatable flow for writing and running Playwright end-to-end (E2E) UI tests in this repository.

## Principles

1. **Locators over Selectors**: Use user-facing attributes (`getByRole`, `getByText`, `getByLabel`) rather than CSS selectors or test IDs, unless absolute necessary. This ensures the tests behave like actual users.
2. **Setup and Teardown**: Utilize Playwright's fixtures and global setups to ensure a clean state (e.g., clearing cookies, resetting DB if needed) before each test.
3. **Resilience**: Wait for network idle or specific UI states (`toBeVisible`, `toBeEnabled`) instead of arbitrary timeouts (`waitForTimeout`). 
4. **Modularity**: Break down complex test flows into Page Object Models (POM) or helper functions to reuse steps (e.g., login, search).

## Directory Structure
- `tests/e2e-ui/` : Store your standard Playwright UI automation specs here (e.g. `login.spec.ts`, `search.spec.ts`).
- `playwright.ui.config.ts`: Playwright configuration specific for UI tests. 

## Command Flow
- To run tests: `pnpm test:ui`
- To run a specific test: `pnpm test:ui tests/e2e-ui/login.spec.ts`
- To run in UI mode: `pnpm test:ui --ui`

## Best Practices
- Every test file should test a specific user journey.
- Validate ARIA and accessibility while doing functional checks if possible.
- Avoid relying on third-party external data that might change; mock endpoints when necessary, or ensure test data is isolated.
