# OPM diagram → MATLAB System Composer

Turn an OPM diagram drawn in yEd with the `yEd_OPM_Palette` into three
System Composer artifacts:

1. a **functional architecture**: what the system does
2. a **logical architecture**: what the system is made of
3. an **allocation set**: which function runs on which component

## The mapping

| In the yEd diagram                         | In System Composer                                     |
|--------------------------------------------|--------------------------------------------------------|
| Process: blue **ellipse**                  | Component in `FunctionalArchitecture.slx`              |
| Object: **green** rectangle (`#339966`)    | Component in `LogicalArchitecture.slx`                 |
| Link between a process and an object       | Allocation *function → component* in `FunctionalToLogical.mldatx` |
| Link between two objects or two processes  | skipped (not a function↔component relation)            |
| States, groups, other shapes               | ignored                                                |

The node's label becomes the component name. The arrow direction doesn't
matter: an instrument link *Grinder → Grinding* and a result link
*Grinding → Ground Coffee* both become allocations from the function
*Grinding*.

```
   yEd / OPM                        System Composer

  ( Grinding )  ──────────────►  FunctionalArchitecture: [Grinding]
       ▲                                                     │ allocated to
       │ instrument                                          ▼
  [ Grinder  ]  ──────────────►  LogicalArchitecture:    [Grinder]
```

## Requirements

- MATLAB with Simulink and System Composer (uses the `arguments` block
  and `Name=Value` syntax, so R2021a or newer)
- A diagram drawn with the palette from this repo (`yEd_OPM_Palette.graphml`),
  saved as `.graphml`

## Quick start

Run the bundled example from the `matlab/` folder:

```matlab
run_coffee_machine_example
```

It converts [`graphml/testdata/coffee_machine.graphml`](../graphml/testdata/coffee_machine.graphml)
(4 processes, 12 objects, 12 process↔object links, 5 structural links)
into `matlab/out/` (it shows how to pass the three output file names), then opens both models and the Allocation Editor.

For your own diagram:

```matlab
result = opm2systemcomposer("my_system.graphml");
```

## Options

All options are passed as `Name=Value`:

| Option                | Default                        | Meaning                                         |
|-----------------------|--------------------------------|-------------------------------------------------|
| `FunctionalModelFile` | `"FunctionalArchitecture.slx"` | Output file of the functional architecture      |
| `LogicalModelFile`    | `"LogicalArchitecture.slx"`    | Output file of the logical architecture         |
| `AllocationSetFile`   | `"FunctionalToLogical.mldatx"` | Output file of the allocation set               |
| `ObjectBorderColor`   | `"#339966"`                    | Border color that marks a box as an OPM object  |
| `Overwrite`           | `false`                        | Replace output from a previous run              |
| `Open`                | `true`                         | Open the models and Allocation Editor when done |

### Choosing the output files

Each of the three `...File` options accepts:

- a **bare name**, `"DroneFunctions.slx"`, which is written to the current folder
- a **relative path**, `"build/DroneFunctions.slx"`, which is resolved from the current folder
- an **absolute path**, `"/data/models/DroneFunctions.slx"`

Missing folders are created. You can leave out the extension (`.slx` or `.mldatx`);
it is added for you.

The file name without its extension also becomes the **model name**
(or allocation set name). Simulink requires model names to be valid MATLAB
identifiers: start with a letter, then use only letters, digits and
underscores. So `Drone_Functions.slx` works, but `drone-functions.slx` or
`2nd model.slx` are rejected with a clear error before anything is created.
The two models also need different names.

Example:

```matlab
result = opm2systemcomposer("my_system.graphml", ...
    FunctionalModelFile="build/MySystemFunctions.slx", ...
    LogicalModelFile="build/MySystemComponents.slx", ...
    AllocationSetFile="build/MySystemAllocation.mldatx", ...
    Overwrite=true, Open=false);
```

## What you get back

The three files named by the options above (defaults shown):

| File                         | Contents                                                       |
|------------------------------|----------------------------------------------------------------|
| `FunctionalArchitecture.slx` | One component per process                                      |
| `LogicalArchitecture.slx`    | One component per object                                       |
| `FunctionalToLogical.mldatx` | Allocation set; open it in the Allocation Editor to see the allocation matrix |

And a `result` struct for further scripting:

| Field             | Contents                                                       |
|-------------------|----------------------------------------------------------------|
| `FunctionalModel` | `systemcomposer.arch.Model` handle                             |
| `LogicalModel`    | `systemcomposer.arch.Model` handle                             |
| `AllocationSet`   | `systemcomposer.allocation.AllocationSet` handle               |
| `Files`           | Full paths: `Files.FunctionalModel`, `Files.LogicalModel`, `Files.AllocationSet` |
| `Processes`       | table `Id, Name, Type, Essence, Affiliation`                   |
| `Objects`         | table `Id, Name, Type, Essence, Affiliation`                   |
| `Allocations`     | table `Function, Component, LinkType, EdgeId`, one row per link |

`LinkType` names the OPM link the arrow heads stand for: `agent`,
`instrument`, `consumption`, `result` or `effect`.

## Good to know

- **Duplicate labels** get a numeric suffix (`Pump`, `Pump_1`), because
  names have to be unique within a model. A `/` in a label becomes `-`,
  because Simulink uses `/` in block paths. Unlabelled nodes are named after
  their GraphML id (e.g. `n7`).
- **Several links between the same pair**, e.g. a process that both consumes
  and yields the same object, give one allocation. The `Allocations` table
  still lists every link.
- **Existing output** is never overwritten silently: the function errors
  unless you pass `Overwrite=true`, which closes the old models and
  allocation set and deletes their files first.
- **Objects are recognised by color.** If you recolored the object boxes,
  pass their border color via `ObjectBorderColor`.
- **Reopening later:** the allocation set refers to the two models by
  name. If you put the files in different folders, add those folders to
  the MATLAB path (`addpath`) before opening the `.mldatx` file.
- The models only hold components: no ports or connectors are created.
  Add those in System Composer once you've reviewed the components.

## Files

| File                                        | Purpose                                 |
|---------------------------------------------|-----------------------------------------|
| `opm2systemcomposer.m`                      | The conversion function (`help opm2systemcomposer`) |
| `run_coffee_machine_example.m`              | Runnable example                        |
| `../graphml/testdata/coffee_machine.graphml`| Example OPM diagram built from the palette styles |
