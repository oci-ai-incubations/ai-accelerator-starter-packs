# cuOpt UI Tests

18 tests executed via Playwright in a **single browser context** with **continuous video recording**. Execute in order — solving (CU-10) must complete before result tests.

**MANDATORY:** Execute ALL tests in order. If a test fails, record the failure, refresh the page, and continue. Do NOT skip any test.

**No authentication required.** The cuOpt frontend has no login.

**This is a single-page app.** All UI lives at `/`. Three left-panel tabs (Problem, Map, Settings) and a right panel with results + chat. No client-side routing — tab switching is done by clicking tab elements.

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
- **Selector:** Oracle logo image (`img[src*="oracle"]` or `img[alt*="Oracle"]`), title text "Vehicle Routing Optimization with cuOpt"
- **Interaction:** None (visual check)
- **Verify:**
  - Oracle logo image is visible
  - Title text containing "Vehicle Routing" or "cuOpt" is visible
  - "Find Optimal Routes" button is visible and enabled

### CU-2: Problem Tab — Fleet Table (P0 smoke, 30s)

- **Area:** Left panel, "Problem" tab (default active)
- **Selector:** Table with columns: Vehicle, Type, Capacity, Shift, Max Route Time
- **Interaction:** Verify table is visible on page load (no click needed — Problem tab is default)
- **Verify:**
  - Table has >=2 rows (Car-1 and Truck-1)
  - "Car-1" and "Truck-1" text visible in table cells
  - Capacity values visible (20 and 50)
  - Type column shows "Car" and "Truck"

### CU-3: Problem Tab — Delivery Stops Table (P0 smoke, 30s)

- **Area:** Left panel, "Problem" tab
- **Selector:** Second table with columns: #, Customer, Address, Time Window, Demand, Service Time, Value
- **Interaction:** Scroll down if needed to see the delivery stops table
- **Verify:**
  - Table has >=6 rows (default problem has 6 deliveries)
  - Customer names visible (e.g., text containing customer identifiers)
  - Address column has values (Austin TX addresses)
  - Demand column has numeric values
  - Time Window column has time ranges

### CU-4: Problem Tab — Summary Chips (P1 smoke, 30s)

- **Area:** Left panel, "Problem" tab
- **Selector:** Chip/badge components showing vehicle count and stop count
- **Interaction:** None (visual check)
- **Verify:**
  - A chip/badge showing "2" (vehicles) is visible
  - A chip/badge showing "6" (delivery stops) is visible

### CU-5: Map Tab — Map Renders (P1 smoke, 30s)

- **Area:** Left panel, "Map" tab
- **Selector:** Tab label "Map", then Leaflet map container (`.leaflet-container`)
- **Interaction:** Click the "Map" tab
- **Verify:**
  - Tab switches to show a Leaflet map
  - Map tiles are loaded (OpenStreetMap tiles visible)
  - Map is centered on Austin TX area
  - "COMING SOON" overlay text is visible (expected behavior)

### CU-6: Map Tab — Markers Visible (P1 smoke, 30s)

- **Area:** Left panel, "Map" tab (already active from CU-5)
- **Selector:** Leaflet marker elements (`.leaflet-marker-icon` or custom DivIcon markers)
- **Interaction:** None (visual check)
- **Verify:**
  - >=7 markers visible on the map (1 depot + 6 delivery stops)
  - Red square marker visible (depot)
  - Teal circle markers visible (delivery stops)

### CU-7: Map Tab — Marker Popup (P2 e2e, 30s)

- **Area:** Left panel, "Map" tab
- **Selector:** Any delivery stop marker (teal circle)
- **Interaction:** Click a delivery stop marker
- **Verify:**
  - Popup appears with stop information
  - Popup contains: stop number, customer name, address
  - **Dismiss the popup** (click elsewhere or press Escape) before continuing

### CU-8: Settings Tab — Model Dropdown (P0 smoke, 30s)

- **Area:** Left panel, "Settings" tab
- **Selector:** Tab label "Settings", then a Select/dropdown component for "AI Model"
- **Interaction:** Click the "Settings" tab, then click the model dropdown
- **Verify:**
  - Settings tab content is visible
  - "AI Model" label is present
  - Dropdown has >=1 model option (populated from `/v1/models`)
  - A model is selected (not empty/placeholder)
- **Note:** If the dropdown is disabled and shows "Loading models...", the LlamaStack pod may not be ready yet. Wait up to 30 seconds for it to enable.

### CU-9: Chat Interface — Visible and Input Works (P0 smoke, 30s)

- **Area:** Right panel, bottom section
- **Selector:** Text input field (placeholder containing "Ask" or "modify" or "solve" or "chat"), Send button
- **Interaction:**
  1. Click the "Problem" tab to return to default view (ensures right panel is visible)
  2. Locate the chat input field
  3. Type "hello" into the input
  4. Verify text appears in the input
  5. Clear the input (do NOT send — just verify input works)
- **Verify:**
  - Chat input field is visible and editable
  - Send button is visible
  - Example query chips are visible (e.g., "Add car", "Add truck", "Add 3 more delivery locations")

### CU-10: Solve — Click "Find Optimal Routes" (P0 e2e, 5min timeout)

- **Area:** Header button + Results area
- **Selector:** Button containing "Find Optimal Routes" or "Optimal" text
- **Interaction:**
  1. Click "Find Optimal Routes" button
  2. Verify button shows loading state ("Finding routes..." with spinner)
  3. Wait for results to appear in the right panel (replaces the delivery schedule)
- **Verify:**
  - Button enters loading state when clicked
  - After solve completes: results summary is visible (vehicle count, delivery count, solve time)
  - No error alert visible
- **CRITICAL:** Solver may take 10-60 seconds (first solve is slower due to cold start). Set timeout appropriately. Update banner periodically: "CU-10: Solving... Xs elapsed". Do NOT click the button again while solving.

### CU-11: Results — Summary Bar (P0 smoke, 30s)

- **Area:** Right panel, results section (after CU-10 solve)
- **Selector:** Paper/card component showing summary statistics
- **Interaction:** None (visual check)
- **Verify:**
  - Vehicle count displayed (number, e.g., "2")
  - Delivery count displayed (number, e.g., "6" or less if some dropped)
  - Solve time displayed (number with units, e.g., "1.23s")

### CU-12: Results — Vehicle Routes Accordion (P0 e2e, 30s)

- **Area:** Right panel, results section
- **Selector:** Accordion/expandable section labeled "Vehicle Routes" or similar
- **Interaction:**
  1. Locate the vehicle routes section (should be expanded by default)
  2. Verify per-vehicle cards are visible
- **Verify:**
  - >=1 vehicle route card visible (e.g., "Car-1" or "Truck-1")
  - Each card shows the vehicle ID
  - Each card shows a delivery count

### CU-13: Results — Route Segments Detail (P1 e2e, 30s)

- **Area:** Right panel, inside a vehicle route card
- **Selector:** Ordered list or table inside a vehicle route card
- **Interaction:** Read the route segments within the first vehicle card
- **Verify:**
  - Route starts from Depot (first segment "From: Depot" or node 0)
  - Route ends at Depot (last segment returns to Depot)
  - Each segment shows: From location, To location, drive time, arrival time
  - Customer names visible in route stops

### CU-14: Results — Capacity Utilization (P1 smoke, 30s)

- **Area:** Right panel, inside vehicle route cards
- **Selector:** Text showing demand/capacity ratio or percentage
- **Interaction:** None (visual check)
- **Verify:**
  - Each vehicle card shows capacity utilization (e.g., "25/50" or "50%")
  - Demand total per vehicle does not exceed capacity

### CU-15: Results — Dropped Tasks Section (P1 smoke, 30s)

- **Area:** Right panel, results section
- **Selector:** Accordion/section labeled "Dropped Tasks" or warning chip
- **Interaction:**
  1. Look for a "Dropped Tasks" accordion or section
  2. If present and has items, expand it
  3. If no tasks were dropped, verify the section shows 0 or is absent
- **Verify:**
  - If dropped tasks exist: expandable section shows customer names and drop reasons
  - If no dropped tasks: section shows "0" or is not displayed (both valid)
- **Note:** With the default problem (6 deliveries, 2 vehicles with capacity 20+50=70, total demand ~50), all tasks may fit — dropped tasks section may be empty.

### CU-16: Chat — Send Message and Get Response (P0 e2e, 2min timeout)

- **Area:** Right panel, chat interface
- **Selector:** Chat input field, Send button, message display area
- **Interaction:**
  1. Type "What is cuOpt?" into the chat input
  2. Click Send (or press Enter)
  3. Verify user message appears in chat (right-aligned)
  4. Wait for AI response (left-aligned message)
- **Verify:**
  - User message "What is cuOpt?" appears in the chat
  - "Thinking..." indicator appears briefly
  - AI response appears with non-empty text about cuOpt/vehicle routing
  - Response is left-aligned with different background color from user message
- **CRITICAL:** LLM response may take 10-30 seconds. Wait patiently. Update banner: "CU-16: Waiting for AI response... Xs elapsed".

### CU-17: Chat — Example Chip Click (P2 smoke, 30s)

- **Area:** Right panel, chat interface
- **Selector:** Chip/button elements with example queries (e.g., "Add car", "Add truck", "Add 3 more delivery locations")
- **Interaction:**
  1. Locate example query chips below the chat input
  2. Click the "Add car" chip (or first available example chip)
  3. Verify the chip text populates the input field
  4. Clear the input (do NOT send — this is just testing the chip interaction)
- **Verify:**
  - Clicking the chip populates the chat input with the chip's text
  - Input field is not empty after chip click

### CU-18: Chat — Modify Problem via AI (P0 e2e, 3min timeout)

- **Area:** Chat interface + Problem tab
- **Selector:** Chat input, Send button, fleet table in Problem tab
- **Interaction:**
  1. Type "Add a truck to the fleet" in the chat input
  2. Click Send
  3. Wait for AI response
  4. Switch to "Problem" tab
  5. Check the fleet table for a new vehicle
- **Verify:**
  - AI responds acknowledging the modification (message about adding a truck)
  - Fleet table now shows >=3 vehicles (was 2 before: Car-1, Truck-1 + new truck)
  - The new vehicle appears with type "Truck" and capacity 50
- **Note:** The LLM uses function calling (`add_truck` tool) to modify the problem. If function calling fails, the LLM falls back to prompt-based modification. Either way, the problem should update.
- **CRITICAL:** After the AI modifies the problem, it may auto-trigger a solve. If a solve starts, wait for it to complete before verifying the fleet table. Update banner: "CU-18: Waiting for AI to modify problem... Xs elapsed".
