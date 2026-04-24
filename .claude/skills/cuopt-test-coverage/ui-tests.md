# cuOpt UI Tests

18 tests executed via **agent-browser** in a **single browser session** with **screenshot evidence at each step**. Execute in order — solving (CU-10) must complete before result tests.

**MANDATORY:** Execute ALL tests in order. If a test fails, record the failure, reload the page, and continue. Do NOT skip any test.

**No authentication required.** The cuOpt frontend has no login.

**This is a single-page app.** All UI lives at `/`. Three left-panel tabs (Problem, Map, Settings) and a right panel with results + chat. No client-side routing — tab switching is done by clicking tab elements.

---

## Session Setup

```bash
EVIDENCE_DIR="/tmp/cuopt-evidence-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"
# AGENT_BROWSER_SESSION is inherited from the calling /testing-pack session (see CRITICAL RULE #5 in /testing-pack/SKILL.md).
BASE_URL="$STARTER_PACK_URL"
agent-browser --headed --ignore-https-errors open "$BASE_URL"
agent-browser wait --load networkidle
agent-browser wait 3000
```

## Test Pattern

Every test follows this cycle:
1. `agent-browser snapshot -i` — capture interactive element refs
2. Find the relevant `@ref` for the element to interact with
3. Interact: `click`, `fill`, `select`, etc.
4. Re-snapshot or use `wait` to confirm the result
5. `agent-browser screenshot "$EVIDENCE_DIR/CU-XX-name.png"` — capture evidence

---

## Execution Order

| # | ID | Test | Tab/Area | P | Type | Timeout |
|---|---|---|---|---|---|---|
| 1 | CU-1 | Header renders | Header | P0 | smoke | 30s |
| 2 | CU-2 | Problem tab — fleet table | Problem | P0 | smoke | 30s |
| 3 | CU-3 | Problem tab — delivery stops table | Problem | P0 | smoke | 30s |
| 4 | CU-4 | Problem tab — summary chips | Problem | P1 | smoke | 30s |
| 5 | CU-5 | Map tab — map renders | Map | P1 | smoke | 30s |
| 6 | CU-6 | Map tab — markers visible | Map | P1 | smoke | 30s |
| 7 | CU-7 | Map tab — marker popup | Map | P2 | e2e | 30s |
| 8 | CU-8 | Settings tab — model dropdown | Settings | P0 | smoke | 30s |
| 9 | CU-9 | Chat interface — visible and input works | Chat | P0 | smoke | 30s |
| 10 | CU-10 | Solve — click "Find Optimal Routes" | Header + Results | P0 | e2e | **5min** |
| 11 | CU-11 | Results — summary bar | Results | P0 | smoke | 30s |
| 12 | CU-12 | Results — vehicle routes accordion | Results | P0 | e2e | 30s |
| 13 | CU-13 | Results — route segments detail | Results | P1 | e2e | 30s |
| 14 | CU-14 | Results — capacity utilization | Results | P1 | smoke | 30s |
| 15 | CU-15 | Results — dropped tasks section | Results | P1 | smoke | 30s |
| 16 | CU-16 | Chat — send message and get response | Chat | P0 | e2e | **2min** |
| 17 | CU-17 | Chat — example chip click | Chat | P2 | smoke | 30s |
| 18 | CU-18 | Chat — modify problem via AI | Chat | P0 | e2e | **3min** |

---

## Critical Context

### Single-page app structure
The entire app is at `/`. The left panel has three tabs controlled by MUI Tab components:
- Tab 0: "Problem" (default active)
- Tab 1: "Map"
- Tab 2: "Settings"

The right panel always shows the results area (top) and chat interface (bottom). Tab switching is done by clicking the tab labels — there is no URL change.

### Default problem on load
The app loads with a pre-configured problem: 6 delivery stops in Austin TX, 2 vehicles (Car-1 capacity 20, Truck-1 capacity 50). This data is visible immediately — no user action needed.

### Chat-driven modifications
The chat interface uses an LLM with function calling to modify the problem data. Available tools: `add_car`, `add_truck`, `remove_vehicle`, `modify_vehicle_capacity`, `modify_all_vehicle_capacities`, `add_delivery_location`, `add_delivery_locations`, `modify_time_limit`. After modification, the LLM may auto-trigger a solve.

---

## Test Details

### CU-1: Header Renders (P0 smoke, 30s)

- **Area:** Header (top of page)
- **Interaction:** Take a snapshot and verify header elements are present
- **Steps:**
  1. `agent-browser snapshot -i` — look for Oracle logo image and title text
  2. Verify Oracle logo image is visible in the snapshot
  3. Verify title text containing "Vehicle Routing" or "cuOpt" is visible
  4. Verify "Find Optimal Routes" button is visible (note its `@ref` for CU-10)
  5. `agent-browser screenshot "$EVIDENCE_DIR/CU-01-header.png"`
- **Verify:**
  - Oracle logo image is visible
  - Title text containing "Vehicle Routing" or "cuOpt" is visible
  - "Find Optimal Routes" button is visible and enabled

### CU-2: Problem Tab — Fleet Table (P0 smoke, 30s)

- **Area:** Left panel, "Problem" tab (default active)
- **Interaction:** Verify table is visible on page load (no click needed — Problem tab is default)
- **Steps:**
  1. `agent-browser snapshot -i` — look for table with columns: Vehicle, Type, Capacity, Shift, Max Route Time
  2. Use `get text` on table cells to verify "Car-1", "Truck-1", capacity values
  3. `agent-browser screenshot "$EVIDENCE_DIR/CU-02-fleet-table.png"`
- **Verify:**
  - Table has >=2 rows (Car-1 and Truck-1)
  - "Car-1" and "Truck-1" text visible in table cells
  - Capacity values visible (20 and 50)
  - Type column shows "Car" and "Truck"

### CU-3: Problem Tab — Delivery Stops Table (P0 smoke, 30s)

- **Area:** Left panel, "Problem" tab
- **Interaction:** Scroll down if needed to see the delivery stops table
- **Steps:**
  1. `agent-browser scroll down 500` — scroll to reveal delivery stops table
  2. `agent-browser snapshot -i` — look for table with columns: #, Customer, Address, Time Window, Demand, Service Time, Value
  3. Use `get text` on cells to verify customer names, addresses, demand values
  4. `agent-browser screenshot "$EVIDENCE_DIR/CU-03-delivery-stops.png"`
- **Verify:**
  - Table has >=6 rows (default problem has 6 deliveries)
  - Customer names visible (e.g., text containing customer identifiers)
  - Address column has values (Austin TX addresses)
  - Demand column has numeric values
  - Time Window column has time ranges

### CU-4: Problem Tab — Summary Chips (P1 smoke, 30s)

- **Area:** Left panel, "Problem" tab
- **Interaction:** None (visual check via snapshot)
- **Steps:**
  1. `agent-browser snapshot -i` — look for chip/badge components showing vehicle count and stop count
  2. Use `get text` on chip elements to verify counts
  3. `agent-browser screenshot "$EVIDENCE_DIR/CU-04-summary-chips.png"`
- **Verify:**
  - A chip/badge showing "2" (vehicles) is visible
  - A chip/badge showing "6" (delivery stops) is visible

### CU-5: Map Tab — Map Renders (P1 smoke, 30s)

- **Area:** Left panel, "Map" tab
- **Interaction:** Click the "Map" tab
- **Steps:**
  1. `agent-browser snapshot -i` — find the "Map" tab `@ref`
  2. Click the "Map" tab (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `(Array.from(document.querySelectorAll('[role="tab"], button, a')).find(el => (el.textContent || '').trim() === 'Map' || el.getAttribute('aria-label') === 'Map'))?.click();`
     `EOF`
  3. `agent-browser wait 2000` — wait for map tiles to load
  4. `agent-browser snapshot -i` — verify Leaflet map container is present
  5. `agent-browser screenshot "$EVIDENCE_DIR/CU-05-map-renders.png"`
- **Verify:**
  - Tab switches to show a Leaflet map
  - Map tiles are loaded (OpenStreetMap tiles visible)
  - Map is centered on Austin TX area
  - "COMING SOON" overlay text is visible (expected behavior)

### CU-6: Map Tab — Markers Visible (P1 smoke, 30s)

- **Area:** Left panel, "Map" tab (already active from CU-5)
- **Interaction:** None (visual check via snapshot)
- **Steps:**
  1. `agent-browser snapshot -i` — look for marker elements on the map
  2. `agent-browser screenshot "$EVIDENCE_DIR/CU-06-markers.png"`
- **Verify:**
  - >=7 markers visible on the map (1 depot + 6 delivery stops)
  - Red square marker visible (depot)
  - Teal circle markers visible (delivery stops)

### CU-7: Map Tab — Marker Popup (P2 e2e, 30s)

- **Area:** Left panel, "Map" tab
- **Interaction:** Click a delivery stop marker
- **Steps:**
  1. `agent-browser snapshot -i` — find a delivery stop marker `@ref` (teal circle)
  2. Click the first delivery stop marker on the map (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `(document.querySelectorAll('.leaflet-marker-icon')[0] || document.querySelectorAll('path[stroke*="teal" i], circle[fill*="teal" i]')[0] || document.querySelectorAll('.leaflet-interactive')[1])?.click();`
     `EOF`
  3. `agent-browser wait 1000` — wait for popup
  4. `agent-browser snapshot -i` — verify popup content
  5. `agent-browser screenshot "$EVIDENCE_DIR/CU-07-marker-popup.png"`
  6. **Dismiss the popup** — click elsewhere on the map or press Escape: `agent-browser press Escape`
- **Verify:**
  - Popup appears with stop information
  - Popup contains: stop number, customer name, address
  - **Dismiss the popup** before continuing

### CU-8: Settings Tab — Model Dropdown (P0 smoke, 30s)

- **Area:** Left panel, "Settings" tab
- **Interaction:** Click the "Settings" tab, then click the model dropdown
- **Steps:**
  1. `agent-browser snapshot -i` — find the "Settings" tab `@ref`
  2. Click the "Settings" tab (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `(Array.from(document.querySelectorAll('[role="tab"], button, a')).find(el => (el.textContent || '').trim() === 'Settings' || el.getAttribute('aria-label') === 'Settings'))?.click();`
     `EOF`
  3. `agent-browser wait 1000`
  4. `agent-browser snapshot -i` — find the "AI Model" dropdown `@ref`
  5. Click the "AI Model" dropdown to open it (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `(Array.from(document.querySelectorAll('button, [role="combobox"], [role="button"], select')).find(el => /ai model|model/i.test((el.textContent || '') + ' ' + (el.getAttribute('aria-label') || ''))))?.click();`
     `EOF`
  6. `agent-browser snapshot -i` — verify dropdown options are present
  7. `agent-browser screenshot "$EVIDENCE_DIR/CU-08-settings-dropdown.png"`
  8. `agent-browser press Escape` — close the dropdown
- **Verify:**
  - Settings tab content is visible
  - "AI Model" label is present
  - Dropdown has >=1 model option (populated from `/v1/models`)
  - A model is selected (not empty/placeholder)
- **Note:** If the dropdown is disabled and shows "Loading models...", the LlamaStack pod may not be ready yet. Wait up to 30 seconds for it to enable.

### CU-9: Chat Interface — Visible and Input Works (P0 smoke, 30s)

- **Area:** Right panel, bottom section
- **Interaction:**
  1. Click the "Problem" tab to return to default view (ensures right panel is visible)
  2. Locate the chat input field
  3. Type "hello" into the input
  4. Verify text appears in the input
  5. Clear the input (do NOT send — just verify input works)
- **Steps:**
  1. `agent-browser snapshot -i` — find the "Problem" tab `@ref`
  2. Click the "Problem" tab (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `(Array.from(document.querySelectorAll('[role="tab"], button, a')).find(el => (el.textContent || '').trim() === 'Problem' || el.getAttribute('aria-label') === 'Problem'))?.click();`
     `EOF`
  3. `agent-browser snapshot -i` — find the chat input field `@ref` (placeholder containing "Ask" or "modify" or "solve" or "chat") and Send button
  4. `agent-browser fill @ref "hello"` — type into the chat input
  5. `agent-browser snapshot -i` — verify "hello" appears in the input
  6. `agent-browser fill @ref ""` — clear the input (do NOT send)
  7. `agent-browser screenshot "$EVIDENCE_DIR/CU-09-chat-input.png"`
- **Verify:**
  - Chat input field is visible and editable
  - Send button is visible
  - Example query chips are visible (e.g., "Add car", "Add truck", "Add 3 more delivery locations")

### CU-10: Solve — Click "Find Optimal Routes" (P0 e2e, 5min timeout)

- **Area:** Header button + Results area
- **Interaction:**
  1. Click "Find Optimal Routes" button
  2. Verify button shows loading state ("Finding routes..." with spinner)
  3. Wait for results to appear in the right panel (replaces the delivery schedule)
- **Steps:**
  1. `agent-browser snapshot -i` — find the "Find Optimal Routes" button `@ref`
  2. Click "Find Optimal Routes" to start solving (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `Array.from(document.querySelectorAll('button, a, [role="button"]')).find(el => (el.textContent || '').trim() === 'Find Optimal Routes' || el.getAttribute('aria-label') === 'Find Optimal Routes')?.click();`
     `EOF`
  3. `agent-browser wait 2000`
  4. `agent-browser snapshot -i` — verify loading state (button text changes to "Finding routes...")
  5. `agent-browser screenshot "$EVIDENCE_DIR/CU-10-solving.png"`
  6. **Poll for completion:** In a loop (up to 60 iterations, 5 seconds apart):
     - `agent-browser wait 5000`
     - `agent-browser snapshot -i` — check if results summary is visible (vehicle count, delivery count, solve time) or if button has returned to normal state
     - If results are visible, break out of the loop
  7. `agent-browser screenshot "$EVIDENCE_DIR/CU-10-solved.png"`
- **Verify:**
  - Button enters loading state when clicked
  - After solve completes: results summary is visible (vehicle count, delivery count, solve time)
  - No error alert visible
- **CRITICAL:** Solver may take 10-60 seconds (first solve is slower due to cold start). Do NOT click the button again while solving.

### CU-11: Results — Summary Bar (P0 smoke, 30s)

- **Area:** Right panel, results section (after CU-10 solve)
- **Interaction:** None (visual check via snapshot)
- **Steps:**
  1. `agent-browser snapshot -i` — look for summary statistics in results area
  2. Use `get text` on summary elements to extract vehicle count, delivery count, solve time
  3. `agent-browser screenshot "$EVIDENCE_DIR/CU-11-summary-bar.png"`
- **Verify:**
  - Vehicle count displayed (number, e.g., "2")
  - Delivery count displayed (number, e.g., "6" or less if some dropped)
  - Solve time displayed (number with units, e.g., "1.23s")

### CU-12: Results — Vehicle Routes Accordion (P0 e2e, 30s)

- **Area:** Right panel, results section
- **Interaction:**
  1. Locate the vehicle routes section (should be expanded by default)
  2. Verify per-vehicle cards are visible
- **Steps:**
  1. `agent-browser snapshot -i` — look for vehicle route cards/accordion sections
  2. Use `get text` on card headers to verify vehicle IDs and delivery counts
  3. `agent-browser screenshot "$EVIDENCE_DIR/CU-12-vehicle-routes.png"`
- **Verify:**
  - >=1 vehicle route card visible (e.g., "Car-1" or "Truck-1")
  - Each card shows the vehicle ID
  - Each card shows a delivery count

### CU-13: Results — Route Segments Detail (P1 e2e, 30s)

- **Area:** Right panel, inside a vehicle route card
- **Interaction:** Read the route segments within the first vehicle card
- **Steps:**
  1. `agent-browser snapshot -i` — find the first vehicle card and its route segments
  2. If the card needs expanding, find and click its expand `@ref`
  3. `agent-browser snapshot -i` — read route segment details
  4. Use `get text` on segment elements to verify From/To locations, drive time, arrival time
  5. `agent-browser screenshot "$EVIDENCE_DIR/CU-13-route-segments.png"`
- **Verify:**
  - Route starts from Depot (first segment "From: Depot" or node 0)
  - Route ends at Depot (last segment returns to Depot)
  - Each segment shows: From location, To location, drive time, arrival time
  - Customer names visible in route stops

### CU-14: Results — Capacity Utilization (P1 smoke, 30s)

- **Area:** Right panel, inside vehicle route cards
- **Interaction:** None (visual check via snapshot)
- **Steps:**
  1. `agent-browser snapshot -i` — look for capacity utilization info in vehicle cards
  2. Use `get text` on capacity elements to extract demand/capacity values
  3. `agent-browser screenshot "$EVIDENCE_DIR/CU-14-capacity.png"`
- **Verify:**
  - Each vehicle card shows capacity utilization (e.g., "25/50" or "50%")
  - Demand total per vehicle does not exceed capacity

### CU-15: Results — Dropped Tasks Section (P1 smoke, 30s)

- **Area:** Right panel, results section
- **Interaction:**
  1. Look for a "Dropped Tasks" accordion or section
  2. If present and has items, expand it
  3. If no tasks were dropped, verify the section shows 0 or is absent
- **Steps:**
  1. `agent-browser snapshot -i` — look for "Dropped Tasks" section
  2. If an expand control is present, click it to expand the "Dropped Tasks" section (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `(Array.from(document.querySelectorAll('button, [role="button"], summary, [aria-expanded]')).find(el => /dropped tasks/i.test((el.textContent || '') + ' ' + (el.getAttribute('aria-label') || ''))))?.click();`
     `EOF`
  3. `agent-browser snapshot -i` — verify dropped tasks content
  4. `agent-browser screenshot "$EVIDENCE_DIR/CU-15-dropped-tasks.png"`
- **Verify:**
  - If dropped tasks exist: expandable section shows customer names and drop reasons
  - If no dropped tasks: section shows "0" or is not displayed (both valid)
- **Note:** With the default problem (6 deliveries, 2 vehicles with capacity 20+50=70, total demand ~50), all tasks may fit — dropped tasks section may be empty.

### CU-16: Chat — Send Message and Get Response (P0 e2e, 2min timeout)

- **Area:** Right panel, chat interface
- **Interaction:**
  1. Type "What is cuOpt?" into the chat input
  2. Click Send (or press Enter)
  3. Verify user message appears in chat (right-aligned)
  4. Wait for AI response (left-aligned message)
- **Steps:**
  1. `agent-browser snapshot -i` — find the chat input `@ref` and Send button `@ref`
  2. `agent-browser fill @ref "What is cuOpt?"` — type the message
  3. Click "Send" to send the message — or `agent-browser press Enter` (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `Array.from(document.querySelectorAll('button, a, [role="button"]')).find(el => (el.textContent || '').trim() === 'Send' || el.getAttribute('aria-label') === 'Send' || el.getAttribute('type') === 'submit')?.click();`
     `EOF`
  4. `agent-browser wait 2000`
  5. `agent-browser snapshot -i` — verify user message appears
  6. **Poll for AI response:** In a loop (up to 24 iterations, 5 seconds apart):
     - `agent-browser wait 5000`
     - `agent-browser snapshot -i` — check for AI response text (left-aligned message about cuOpt/vehicle routing)
     - If AI response is visible, break out of the loop
  7. `agent-browser screenshot "$EVIDENCE_DIR/CU-16-chat-response.png"`
- **Verify:**
  - User message "What is cuOpt?" appears in the chat
  - "Thinking..." indicator appears briefly
  - AI response appears with non-empty text about cuOpt/vehicle routing
  - Response is left-aligned with different background color from user message
- **CRITICAL:** LLM response may take 10-30 seconds. Wait patiently using the polling loop.

### CU-17: Chat — Example Chip Click (P2 smoke, 30s)

- **Area:** Right panel, chat interface
- **Interaction:**
  1. Locate example query chips below the chat input
  2. Click the "Add car" chip (or first available example chip)
  3. Verify the chip text populates the input field
  4. Clear the input (do NOT send — this is just testing the chip interaction)
- **Steps:**
  1. `agent-browser snapshot -i` — find example chip `@ref` (e.g., "Add car", "Add truck", "Add 3 more delivery locations")
  2. Click the first example chip (e.g. "Add car") (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `(Array.from(document.querySelectorAll('button, a, [role="button"], [class*="chip" i]')).find(el => /add car|add truck|add .* delivery|example/i.test((el.textContent || '') + ' ' + (el.getAttribute('aria-label') || ''))))?.click();`
     `EOF`
  3. `agent-browser snapshot -i` — verify the chat input is now populated with the chip's text
  4. Find the chat input `@ref` and `agent-browser fill @ref ""` — clear it (do NOT send)
  5. `agent-browser screenshot "$EVIDENCE_DIR/CU-17-chip-click.png"`
- **Verify:**
  - Clicking the chip populates the chat input with the chip's text
  - Input field is not empty after chip click

### CU-18: Chat — Modify Problem via AI (P0 e2e, 3min timeout)

- **Area:** Chat interface + Problem tab
- **Interaction:**
  1. Type "Add a truck to the fleet" in the chat input
  2. Click Send
  3. Wait for AI response
  4. Switch to "Problem" tab
  5. Check the fleet table for a new vehicle
- **Steps:**
  1. `agent-browser snapshot -i` — find the chat input `@ref` and Send button `@ref`
  2. `agent-browser fill @ref "Add a truck to the fleet"` — type the message
  3. Click "Send" to send the message — or `agent-browser press Enter` (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `Array.from(document.querySelectorAll('button, a, [role="button"]')).find(el => (el.textContent || '').trim() === 'Send' || el.getAttribute('aria-label') === 'Send' || el.getAttribute('type') === 'submit')?.click();`
     `EOF`
  4. `agent-browser wait 2000`
  5. **Poll for AI response:** In a loop (up to 36 iterations, 5 seconds apart):
     - `agent-browser wait 5000`
     - `agent-browser snapshot -i` — check for AI response acknowledging truck addition
     - If AI response about adding a truck is visible, break out of the loop
  6. `agent-browser screenshot "$EVIDENCE_DIR/CU-18-chat-modify.png"`
  7. `agent-browser snapshot -i` — find the "Problem" tab `@ref`
  8. Click the "Problem" tab to switch to it (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `(Array.from(document.querySelectorAll('[role="tab"], button, a')).find(el => (el.textContent || '').trim() === 'Problem' || el.getAttribute('aria-label') === 'Problem'))?.click();`
     `EOF`
  9. `agent-browser wait 2000`
  10. `agent-browser snapshot -i` — verify fleet table now shows >=3 vehicles
  11. `agent-browser screenshot "$EVIDENCE_DIR/CU-18-fleet-updated.png"`
- **Verify:**
  - AI responds acknowledging the modification (message about adding a truck)
  - Fleet table now shows >=3 vehicles (was 2 before: Car-1, Truck-1 + new truck)
  - The new vehicle appears with type "Truck" and capacity 50
- **Note:** The LLM uses function calling (`add_truck` tool) to modify the problem. If function calling fails, the LLM falls back to prompt-based modification. Either way, the problem should update.
- **CRITICAL:** After the AI modifies the problem, it may auto-trigger a solve. If a solve starts, wait for it to complete before verifying the fleet table.

---

## Teardown

After all tests complete (whether passed or failed):

```bash
agent-browser close
echo "Evidence screenshots saved to: $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR"
```
