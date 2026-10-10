function result = opm2systemcomposer(graphmlFile, options)
%OPM2SYSTEMCOMPOSER Turn a yEd OPM diagram into System Composer architectures.
%
%   result = OPM2SYSTEMCOMPOSER(graphmlFile) reads an Object-Process
%   Methodology (OPM) diagram drawn in yEd with the yEd_OPM_Palette and
%   builds three System Composer artifacts from it:
%
%     OPM diagram (yEd)              System Composer
%     -----------------------------  ------------------------------------
%     process  (blue ellipse)    ->  component in the FUNCTIONAL model
%     object   (green rectangle) ->  component in the LOGICAL model
%     process <-> object link    ->  allocation  function -> component
%                                    in the ALLOCATION SET
%
%   Links between two objects (e.g. aggregation) or two processes do not
%   connect a function to a component, so they are skipped. States,
%   groups and anything that is neither an ellipse nor a green rectangle
%   are ignored as well.
%
%   result = OPM2SYSTEMCOMPOSER(graphmlFile, Name=Value) sets options:
%
%     FunctionalModelFile  Output file of the functional architecture.
%                                    Default: "FunctionalArchitecture.slx"
%     LogicalModelFile     Output file of the logical architecture.
%                                    Default: "LogicalArchitecture.slx"
%     AllocationSetFile    Output file of the allocation set (view it in
%                          the Allocation Editor as a table/matrix).
%                                    Default: "FunctionalToLogical.mldatx"
%     ObjectBorderColor    Border color that marks an object box.
%                                    Default: "#339966" (palette green)
%     Overwrite            Replace files from a previous run. Default: false
%     Open                 Open both models and the Allocation Editor
%                          when done.                         Default: true
%
%   About the output files:
%     - A file may be a bare name ("Functions.slx") or a path
%       ("build/Functions.slx"). Relative paths start at the current folder;
%       missing folders are created.
%     - The extension (.slx / .mldatx) may be left out; it is added.
%     - The file name, without extension, becomes the model / allocation
%       set name, so it must be a valid MATLAB identifier: start with a
%       letter, then letters, digits or underscores (e.g. "Drone_Functions").
%
%   The returned struct holds:
%     result.FunctionalModel   systemcomposer.arch.Model
%     result.LogicalModel      systemcomposer.arch.Model
%     result.AllocationSet     systemcomposer.allocation.AllocationSet
%     result.Files             struct with the full paths of the three files
%     result.Processes         table of processes found in the diagram
%     result.Objects           table of objects found in the diagram
%     result.Allocations       table: Function | Component | LinkType | EdgeId
%
%   Example:
%     result = opm2systemcomposer("../graphml/testdata/coffee_machine.graphml", ...
%         FunctionalModelFile="out/CoffeeFunctions.slx", ...
%         LogicalModelFile="out/CoffeeComponents.slx", ...
%         AllocationSetFile="out/CoffeeAllocation.mldatx", ...
%         Overwrite=true);
%     disp(result.Allocations)
%
%   See also systemcomposer.createModel,
%   systemcomposer.allocation.createAllocationSet.

arguments
    graphmlFile {mustBeFile}
    options.FunctionalModelFile {mustBeTextScalar} = "FunctionalArchitecture.slx"
    options.LogicalModelFile {mustBeTextScalar} = "LogicalArchitecture.slx"
    options.AllocationSetFile {mustBeTextScalar} = "FunctionalToLogical.mldatx"
    options.ObjectBorderColor {mustBeTextScalar} = "#339966"
    options.Overwrite (1,1) logical = false
    options.Open (1,1) logical = true
end

% --- Check the output files before doing any work -----------------------
functionalFile = outputFile(options.FunctionalModelFile, ".slx");
logicalFile = outputFile(options.LogicalModelFile, ".slx");
allocationFile = outputFile(options.AllocationSetFile, ".mldatx");
if functionalFile.Name == logicalFile.Name
    error("opm2systemcomposer:SameModelName", ...
        "The functional and logical model files both are named '%s'; " + ...
        "Simulink can't load two models with the same name.", functionalFile.Name);
end

% --- Step 1: read processes, objects and links from the GraphML file ----
[nodes, edges] = readOpmGraphml(absolutePath(graphmlFile), options.ObjectBorderColor);
processes = nodes(nodes.Type == "process", :);
objects = nodes(nodes.Type == "object", :);
if isempty(processes) || isempty(objects)
    error("opm2systemcomposer:NothingToConvert", ...
        "Found %d processes and %d objects in %s; need at least one of each.", ...
        height(processes), height(objects), graphmlFile);
end
% Simulink needs unique block names inside one model.
processes.Name = matlab.lang.makeUniqueStrings(processes.Name);
objects.Name = matlab.lang.makeUniqueStrings(objects.Name);
links = findProcessObjectLinks(edges, nodes);

prepareOutputFiles(functionalFile, logicalFile, allocationFile, options.Overwrite);

% --- Step 2: functional architecture (one component per process) --------
[functionalModel, functionComponents] = buildArchitecture(functionalFile, processes.Name);

% --- Step 3: logical architecture (one component per object) ------------
[logicalModel, logicalComponents] = buildArchitecture(logicalFile, objects.Name);

% --- Step 4: allocation set (one allocation per process-object link) ----
[~, functionIdx] = ismember(links.ProcessId, processes.Id);
[~, componentIdx] = ismember(links.ObjectId, objects.Id);
allocationSet = buildAllocationSet(allocationFile, functionalModel, logicalModel, ...
    functionComponents(functionIdx), logicalComponents(componentIdx));

% --- Results -------------------------------------------------------------
allocations = table(processes.Name(functionIdx), objects.Name(componentIdx), ...
    links.LinkType, links.EdgeId, ...
    VariableNames=["Function" "Component" "LinkType" "EdgeId"]);
files = struct( ...
    "FunctionalModel", functionalFile.Path, ...
    "LogicalModel", logicalFile.Path, ...
    "AllocationSet", allocationFile.Path);
result = struct( ...
    "FunctionalModel", functionalModel, ...
    "LogicalModel", logicalModel, ...
    "AllocationSet", allocationSet, ...
    "Files", files, ...
    "Processes", processes, ...
    "Objects", objects, ...
    "Allocations", allocations);

fprintf("Read %s\n", graphmlFile);
fprintf("  %2d processes -> %s\n", height(processes), functionalFile.Path);
fprintf("  %2d objects   -> %s\n", height(objects), logicalFile.Path);
fprintf("  %2d links     -> %s\n", height(links), allocationFile.Path);
fprintf("  %2d links skipped (not process<->object)\n", height(edges) - height(links));

if options.Open
    open_system(functionalModel.Name);
    open_system(logicalModel.Name);
    systemcomposer.allocation.editor();
end
end


%% ------------------------------------------------------------------------
%  System Composer helpers
%  ------------------------------------------------------------------------

function [model, components] = buildArchitecture(file, componentNames)
%BUILDARCHITECTURE Create a model with one component per name, save to file.
model = systemcomposer.createModel(file.Name);
components = model.Architecture.addComponent(cellstr(componentNames));
try
    Simulink.BlockDiagram.arrangeSystem(file.Name);
catch
    % Auto-layout is cosmetic only; keep the default placement if it fails.
end
save_system(file.Name, file.Path);
end

function allocationSet = buildAllocationSet(file, sourceModel, targetModel, ...
        functionComponents, logicalComponents)
%BUILDALLOCATIONSET Allocate functionComponents(k) to logicalComponents(k).
allocationSet = systemcomposer.allocation.createAllocationSet( ...
    file.Name, sourceModel.Name, targetModel.Name);
scenario = allocationSet.Scenarios(1);
% Two links between the same process and object (e.g. consumption and
% result) still give a single allocation.
allocated = strings(0);
for k = 1:numel(functionComponents)
    pair = functionComponents(k).Name + "->" + logicalComponents(k).Name;
    if ~ismember(pair, allocated)
        scenario.allocate(functionComponents(k), logicalComponents(k));
        allocated(end + 1) = pair; %#ok<AGROW>
    end
end
% A new allocation set is saved to the current folder, so save from there.
previousFolder = cd(file.Folder);
restoreFolder = onCleanup(@() cd(previousFolder));
allocationSet.save();
end

function file = outputFile(path, extension)
%OUTPUTFILE Check an output file option and split it into Path/Folder/Name.
%   Adds the extension if missing and resolves relative paths against the
%   current folder. The name must be valid as a model name.
path = string(path);
[folder, name, ext] = fileparts(path);
if ext == ""
    ext = extension;
elseif ~strcmpi(ext, extension)
    error("opm2systemcomposer:BadExtension", ...
        "Output file '%s' must end in %s.", path, extension);
end
if ~isvarname(name)
    error("opm2systemcomposer:BadFileName", ...
        "Output file name '%s' is not a valid model name. Use a letter " + ...
        "followed by letters, digits or underscores (max %d characters).", ...
        name, namelengthmax);
end
if folder == "" || ~java.io.File(folder).isAbsolute()
    folder = fullfile(pwd, folder);
end
file = struct("Path", fullfile(folder, name + ext), "Folder", folder, "Name", name);
end

function prepareOutputFiles(functionalFile, logicalFile, allocationFile, overwrite)
%PREPAREOUTPUTFILES Create output folders; refuse to clobber unless overwrite.
outputs = [functionalFile, logicalFile, allocationFile];
paths = [outputs.Path];
existing = paths(isfile(paths));
if ~isempty(existing) && ~overwrite
    error("opm2systemcomposer:OutputExists", ...
        "Output already exists: %s. Pass Overwrite=true to replace it.", ...
        strjoin(existing, ", "));
end
for folder = unique([outputs.Folder])
    if ~isfolder(folder)
        mkdir(folder);
    end
end
if ~overwrite
    return
end

% Close what a previous run left open, allocation set first because it
% references both models.
openSet = systemcomposer.allocation.AllocationSet.find(allocationFile.Name);
if ~isempty(openSet)
    openSet.close(true);
end
for name = [functionalFile.Name, logicalFile.Name]
    if bdIsLoaded(name)
        close_system(name, 0);
    end
end
for path = existing
    delete(path);
end
end


%% ------------------------------------------------------------------------
%  GraphML helpers
%  ------------------------------------------------------------------------

function [nodes, edges] = readOpmGraphml(file, objectBorderColor)
%READOPMGRAPHML Read the nodes and edges of a yEd GraphML file into tables.
%   nodes: Id | Name | Type ("process", "object" or "other")
%          | Essence ("physical"/"informational") | Affiliation
%   edges: Id | Source | Target | ArrowTail | ArrowHead
doc = xmlread(file);

nodeList = doc.getElementsByTagName('node');
n = nodeList.getLength;
[Id, Name, Type, Essence, Affiliation] = deal(strings(n, 1));
for k = 1:n
    node = nodeList.item(k - 1);   % Java lists are 0-based
    Id(k) = string(node.getAttribute('id'));
    Type(k) = "other";
    shapeNode = ownShapeNode(node);
    if isempty(shapeNode)
        continue   % e.g. a group node
    end

    shape = attributeOf(firstElement(shapeNode, "y:Shape"), "type");
    border = firstElement(shapeNode, "y:BorderStyle");
    if shape == "ellipse"
        Type(k) = "process";
    elseif shape == "rectangle" && ...
            strcmpi(attributeOf(border, "color"), objectBorderColor)
        Type(k) = "object";
    end

    % Palette convention: drop shadow = physical, dashed border = environmental.
    Essence(k) = "informational";
    if ~isempty(firstElement(shapeNode, "y:DropShadow"))
        Essence(k) = "physical";
    end
    Affiliation(k) = "systemic";
    if attributeOf(border, "type") ~= "line" && attributeOf(border, "type") ~= ""
        Affiliation(k) = "environmental";
    end

    Name(k) = componentName(labelText(shapeNode), Id(k));
end
nodes = table(Id, Name, Type, Essence, Affiliation);

edgeList = doc.getElementsByTagName('edge');
m = edgeList.getLength;
[Id, Source, Target, ArrowTail, ArrowHead] = deal(strings(m, 1));
for k = 1:m
    edge = edgeList.item(k - 1);
    Id(k) = string(edge.getAttribute('id'));
    Source(k) = string(edge.getAttribute('source'));
    Target(k) = string(edge.getAttribute('target'));
    arrows = firstElement(edge, "y:Arrows");
    ArrowTail(k) = attributeOf(arrows, "source", "none");
    ArrowHead(k) = attributeOf(arrows, "target", "none");
end
edges = table(Id, Source, Target, ArrowTail, ArrowHead);
end

function links = findProcessObjectLinks(edges, nodes)
%FINDPROCESSOBJECTLINKS Keep only edges between a process and an object.
%   links: EdgeId | ProcessId | ObjectId | LinkType
[~, s] = ismember(edges.Source, nodes.Id);
[~, t] = ismember(edges.Target, nodes.Id);
sourceType = strings(height(edges), 1);
targetType = strings(height(edges), 1);
sourceType(s > 0) = nodes.Type(s(s > 0));
targetType(t > 0) = nodes.Type(t(t > 0));

processToObject = sourceType == "process" & targetType == "object";
objectToProcess = sourceType == "object" & targetType == "process";
keep = processToObject | objectToProcess;

ProcessId = edges.Source;
ProcessId(objectToProcess) = edges.Target(objectToProcess);
ObjectId = edges.Target;
ObjectId(objectToProcess) = edges.Source(objectToProcess);

LinkType = strings(height(edges), 1);
for k = find(keep)'
    LinkType(k) = linkType(edges.ArrowTail(k), edges.ArrowHead(k), objectToProcess(k));
end

links = table(edges.Id(keep), ProcessId(keep), ObjectId(keep), LinkType(keep), ...
    VariableNames=["EdgeId" "ProcessId" "ObjectId" "LinkType"]);
end

function type = linkType(tail, head, pointsToProcess)
%LINKTYPE Name the OPM procedural link drawn with the palette's arrow heads.
if tail == "white_delta" && head == "white_delta"
    type = "effect";
elseif head == "circle"
    type = "agent";
elseif head == "transparent_circle"
    type = "instrument";
elseif head == "white_delta" && pointsToProcess
    type = "consumption";
elseif head == "white_delta"
    type = "result";
else
    type = tail + "->" + head;
end
end

function shapeNode = ownShapeNode(node)
%OWNSHAPENODE The y:ShapeNode in this node's own <data>, not in nested groups.
ELEMENT_NODE = 1;   % org.w3c.dom.Node.ELEMENT_NODE
shapeNode = [];
child = node.getFirstChild;
while ~isempty(child)
    if child.getNodeType == ELEMENT_NODE && string(child.getNodeName) == "data"
        shapeNode = firstElement(child, "y:ShapeNode");
        if ~isempty(shapeNode)
            return
        end
    end
    child = child.getNextSibling;
end
end

function text = labelText(shapeNode)
%LABELTEXT Visible label text of a node, whitespace collapsed to single spaces.
text = "";
label = firstElement(shapeNode, "y:NodeLabel");
if isempty(label)
    return
end
% Only the label's own text; child elements hold layout settings.
TEXT_NODE = 3;            % org.w3c.dom.Node.TEXT_NODE
CDATA_SECTION_NODE = 4;   % org.w3c.dom.Node.CDATA_SECTION_NODE
child = label.getFirstChild;
while ~isempty(child)
    if child.getNodeType == TEXT_NODE || child.getNodeType == CDATA_SECTION_NODE
        text = text + string(child.getData);
    end
    child = child.getNextSibling;
end
text = strtrim(regexprep(text, "\s+", " "));
end

function name = componentName(label, id)
%COMPONENTNAME Turn a label into a valid Simulink block name.
%   "/" separates block paths in Simulink, so it cannot appear in a name.
name = strrep(label, "/", "-");
if name == ""
    name = id;
end
end

function element = firstElement(parent, tag)
%FIRSTELEMENT First descendant element with the given tag, or [] if none.
list = parent.getElementsByTagName(char(tag));
element = [];
if list.getLength > 0
    element = list.item(0);
end
end

function value = attributeOf(element, name, default)
%ATTRIBUTEOF Attribute value as a string, or the default if it is missing.
if nargin < 3
    default = "";
end
value = string(default);
if ~isempty(element) && element.hasAttribute(char(name))
    value = string(element.getAttribute(char(name)));
end
end

function file = absolutePath(file)
%ABSOLUTEPATH Resolve a file path so it survives changing folders.
info = dir(file);
file = fullfile(info.folder, info.name);
end
