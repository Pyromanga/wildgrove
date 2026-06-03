# 🏗️ WildGrove Core Architecture - Technical Specification

This document defines the boot sequence, dependency management, and architectural layers for **WildGrove**.

## 1. The Initialization Pipeline (Boot Sequence)

The `ServiceOrchestrator` (attached to `Main.tscn`) manages the startup flow in 6 distinct phases to ensure zero-pointer exceptions and resolved dependencies.

| Phase | Name | Action |
| --- | --- | --- |
| **1** | **Validate** | `ServiceValidator` checks `BootstrapConfig.tres` for file existence and integrity. |
| **2** | **Resolve** | `ServiceDependencyResolver` sorts services based on their `deps` (Topological Sort). |
| **3** | **Instantiate** | `ServiceFactory` creates instances (`RefCounted` or `Node`) based on definitions. |
| **4** | **Init** | Calls `init()` on all services. Use this to store references to other services. |
| **5** | **Activate** | Calls `on_ready()` on all services. Use this to connect to the `EventBus`. |
| **6** | **Install** | Fills the `Services` Autoload via `populate()` for global type-safe access. |

---

## 2. Core Components

### A. Bootstrap Configuration (`.tres`)

Every system module is registered as a `ServiceDefinition` resource:

* **`service_name`**: The unique key for global access (e.g., `"inventory"`).
* **`path`**: File path to the `.gd` script or `.tscn` scene.
* **`deps`**: Array of service names required to be ready before this one.
* **`required_data_files`**: Data resources (`.tres`) validated before the engine boots.

### B. Base Classes

* **`Service` (RefCounted)**: Pure logic, no performance overhead. Best for Data, Calculations, and Save Systems.
* **`ServiceNode` (Node)**: Services requiring the SceneTree (Timers, Physics, Process-loops).

### C. Lifecycle Interface

Every service must implement or respect these methods:

* `init()`: Cross-referencing other services. No signal connections here.
* `on_ready()`: The system is live. Connect signals and load initial data here.
* `on_cleanup()`: Reverse boot order. Cleanup memory and disconnect listeners.

---

## 3. Global Communication Layers

### Global Access: The `Services` Container

This is the **Type-Safe Service Locator**. It provides autocompletion and prevents "silent fails" via Logger integration.

```gdscript
# Usage Examples:
Services.data.get_player_speed()      # Access static config
Services.inventory.add_item("wood")  # Trigger global logic
Services.quest.start_quest("intro")  # Update game state

```

### Decoupled Messaging: The `EventBus`

Services never call each other's UI or Entity logic directly. They emit signals through dedicated namespaces:

* **`EventBus.system`**: Boot status, saving/loading, state transitions.
* **`EventBus.player`**: Stats, inventory, level-ups.
* **`EventBus.quest`**: Progression, objectives, rewards.

---

## 4. Data-Driven Design (Resources)

Data is strictly separated from logic using Godot Resources (`.tres`):

* **`PlayerData`**: Initial stats like speed, jump force, and gravity.
* **`QuestDefinition`**: Static data including titles, descriptions, and prerequisites.
* **`QuestObjective`**: Sub-resources defining specific goals (Collect, Kill, Interact).
* **`QuestReward`**: Description of rewards (XP, Items, Unlocks).

---

## 5. Development Workflow (Standard Operating Procedure)

To implement a new feature (e.g., "Skill System"):

1. **Define Events**: Create `SkillEvents.gd`, add to `EventBus.gd`.
2. **Logic Container**: Create `SkillService.gd` (inherits from `Service`).
3. **Registration**: Add a `ServiceDefinition` to `BootstrapConfig.tres`.
4. **Integration**: Add `var skill: SkillService` to `Services.gd` and map it in `populate()`.
5. **Data Creation**: Create the necessary `.tres` files for skill-trees or XP-tables.

---

## 6. Error Handling & Safety

* **Logger Fix**: The system uses explicit type casting for LogLevels to prevent Parse Errors.
* **Validator**: The boot process aborts immediately if a file is missing or a circular dependency is detected.
* **Type Guard**: The `Services` container validates that the loaded instance matches the declared class type.

---