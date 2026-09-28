---
name: chrome-control
description: Connect to and control the Google Chrome browser via Chrome DevTools MCP with zero prompts. Use whenever the user asks to connect to Chrome, open a URL, browse a website, test web UI, take screenshots, or automate actions in Chrome.
---

# Chrome Control Skill

This skill guides the agent on connecting to and driving the Google Chrome browser using the configured **Chrome DevTools MCP** server with persistent profile support (zero interactive prompts).

---

## 1. Quick Connection & Verification

When the user asks to **connect to Chrome**, verify the connection status first:

1. Call the `list_pages` tool on the `chrome-devtools` MCP server.
2. If pages are returned (e.g. `## Pages 1: about:blank` or open tabs):
   - Connection is active and ready.
   - Report the currently open tabs/URLs to the user.
3. If no page is open, call `new_page` with the requested URL or `about:blank`.

---

## 2. Core Browser Actions & Available Tools

All tools are provided by the `chrome-devtools` MCP server:

### Navigation & Tab Management
- **List Tabs**: `list_pages()` — Returns all active browser pages/tabs.
- **Open New Tab**: `new_page(url)` — Creates a new tab and navigates to the specified URL.
- **Navigate**: `navigate_page(url)` — Navigates the currently selected tab to the target URL.
- **Select Tab**: `select_page(pageId)` — Switches focus to a specific tab.
- **Close Tab**: `close_page(pageId)` — Closes the specified tab.

### Page Interaction
- **Click**: `click(selector)` or `click(x, y)` — Clicks buttons, links, or specific coordinates.
- **Type Text**: `type_text(selector, text)` — Types into input fields or textareas.
- **Fill Form**: `fill_form(elements)` — Fills multiple form fields in one call.
- **Press Key**: `press_key(key)` — Emulates keyboard presses (e.g., `Enter`, `Tab`, `Escape`).
- **Hover**: `hover(selector)` — Hovers over elements to reveal dropdowns or tooltips.

### Visual & DOM Inspection
- **Take Screenshot**: `take_screenshot()` — Captures the current visible viewport or full page. Always take a screenshot after performing key actions to verify state.
- **DOM Snapshot**: `take_snapshot()` — Dumps the accessible element tree and interactive elements on the page. Use this to find button IDs, links, and input names.
- **Evaluate Script**: `evaluate_script(script)` — Executes arbitrary JavaScript directly in the page context.

### Network & Diagnostics
- **Console Logs**: `list_console_messages()` — Fetches JavaScript console errors, warnings, and logs.
- **Network Requests**: `list_network_requests()` — Inspects HTTP requests, headers, status codes, and responses.

---

## 3. Persistent Profile & Session State

- **Profile Location**: `C:\Users\Mishay\.chrome-mcp-profile`
- **Behavior**:
  - Logins, cookies, local storage, and history are automatically preserved across sessions.
  - No "Allow remote debugging" permission dialog is shown because Chrome is launched in developer mode directly with its own user data directory.

---

## 4. Standard Automation Workflow

When executing a browser task (e.g., "Go to localhost:3000 and test the login form"):

1. **Connect & Navigate**:
   - Check open pages with `list_pages`.
   - Call `navigate_page(url)` (or `new_page(url)`).
2. **Inspect**:
   - Call `take_snapshot()` to locate interactive selectors (e.g., input IDs, button text).
3. **Interact**:
   - Call `type_text` or `fill_form` with the required credentials/data.
   - Call `click` on the submit button.
4. **Verify**:
   - Wait for navigation or state change.
   - Call `take_screenshot()` to visually confirm the result.
   - Call `list_console_messages()` to check for frontend errors.
5. **Report**:
   - Summarize the actions taken, the final page state, and any errors detected.
