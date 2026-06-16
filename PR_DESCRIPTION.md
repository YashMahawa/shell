

# Event-Driven 'Extreme Lite' Engine

## 1. Context & Objectives
*Define the purpose of this initiative and what constitutes a successful outcome from a business and user perspective.*

- **Problem Statement:** Performance-focused users are deterred by Caelestia’s 1.5GB idle memory footprint, which is nearly 8x higher than competing lightweight environments [cite:source4]. Current background services rely on fixed-interval polling that consumes CPU and RAM even when data is static [cite:source1].
- **Business Goal:** Expand adoption among tiling window manager (TWM) enthusiasts by providing a competitive resource profile.
- **Hypothesis:** Refactoring the core engine to use native event triggers instead of polling will reduce the idle resource baseline to under 300MB.
- **Success Metrics:**
    - Idle memory usage reduced by at least 75%.
    - Zero baseline CPU usage from background system monitors when the dashboard is closed.
    - 90% reduction in wallpaper indexing time for large directories.

---

## 2. User Scenarios
*Narrative journeys that describe how a person interacts with the solution. Focus on the experience, not the interface.*

- **Scenario: Lightweight Idle Environment**
    - **User Intent:** A user wants to run a clean TWM environment without sacrificing more than a few hundred megabytes of RAM to the shell.
    - **Desired Experience:** The shell components sit idle with negligible resource impact, only waking up when a system event (like a volume change or notification) occurs.
- **Scenario: Efficient Large Collection Browsing**
    - **User Intent:** A user with thousands of high-resolution wallpapers wants to change themes instantly.
    - **Desired Experience:** The native daemon serves indexed wallpaper metadata instantly, avoiding the lag and memory spikes associated with recursive filesystem scanning [cite:source2].

---

## 3. Functional Requirements
*A high-level list of what the solution must be able to do. Avoid mentioning specific code, databases, or implementation details.*

- **Requirement 1:** Replace the current 1000ms polling cycle for system stats with an event-driven model that only updates on hardware-level changes [cite:source1][cite:source6].
- **Requirement 2:** Implement a native background daemon to handle heavy filesystem operations like recursive wallpaper scanning and image metadata extraction [cite:source2].
- **Requirement 3:** Decouple the monolithic shell into modular components that can be initialized independently to save memory [cite:source3].
- **Requirement 4:** Provide a "True Lite" mode that automatically disables high-GPU blur and glassmorphism effects when system resources are constrained [cite:source5].
- **Requirement 5:** Ensure the theming engine operates as an asynchronous, on-demand process that leaves no memory footprint after execution.

---

## 4. Constraints & Guardrails
- The shell must remain compatible with existing user configuration files.
- Transitioning to a native daemon must not introduce more than 50ms of latency to UI interactions.
- Total idle memory usage must not exceed 300MB on a standard NixOS installation.
- Full support for the existing Quickshell-based UI must be maintained without a complete graphical rewrite.

---

## 5. Acceptance Criteria
*A checklist of conditions that must be met for the solution to be considered complete and successful.*

- [ ] The system idle memory footprint is verified to be under 300MB using standard monitoring tools.
- [ ] Wallpaper selection across a 1000+ image directory completes in under 500ms [cite:source2].
- [ ] System monitor services (CPU/GPU) show 0% CPU utilization in the background [cite:source1].
- [ ] Disabling a shell module through the native daemon successfully releases all associated memory [cite:source3].
- [ ] All event-triggered UI updates occur without visible stutter or thread blocking.