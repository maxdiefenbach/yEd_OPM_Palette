function tests = test_opm2systemcomposer
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
here = fileparts(mfilename("fullpath"));
matlabFolder = fullfile(here, "..");
addpath(matlabFolder);
testCase.addTeardown(@rmpath, matlabFolder);
testCase.TestData.GraphmlFile = fullfile( ...
    here, "..", "..", "graphml", "testdata", "coffee_machine.graphml");
end

function testCoffeeMachineEndToEnd(testCase)
[~, files] = newWorkspace(testCase, "EndToEnd");

result = convert(testCase.TestData.GraphmlFile, files);

verifyEqual(testCase, height(result.Processes), 4);
verifyEqual(testCase, height(result.Objects), 12);
verifyEqual(testCase, height(result.Allocations), 12);
verifyEqual(testCase, ...
    numel(result.AllocationSet.Scenarios(1).Allocations), 12);
verifyTrue(testCase, all(isfile([ ...
    files.FunctionalPath, files.LogicalPath, files.AllocationPath])));
end

function testDistinctNamesContainingArrowAreNotDeduplicated(testCase)
[root, files] = newWorkspace(testCase, "Tuple");
xml = fileread(testCase.TestData.GraphmlFile);
xml = strrep(xml, ">Grinding<", ">A<");
xml = strrep(xml, ">Grinder<", ">B-&gt;C<");
xml = strrep(xml, ">Heating<", ">A-&gt;B<");
xml = strrep(xml, ">Boiler<", ">C<");
graphmlFile = writeGraphml(root, "name_collision.graphml", xml);

result = convert(graphmlFile, files);

verifyEqual(testCase, height(result.Allocations), 12);
verifyEqual(testCase, ...
    numel(result.AllocationSet.Scenarios(1).Allocations), 12);
end

function testReversedEdgeKeepsLinkType(testCase)
[root, files] = newWorkspace(testCase, "Direction");
xml = fileread(testCase.TestData.GraphmlFile);
xml = strrep(xml, ...
    '<edge id="e6" source="n8" target="n12">', ...
    '<edge id="e6" source="n12" target="n8">');
xml = regexprep(xml, ...
    '(<edge id="e6"[\s\S]*?<y:Arrows )source="none" target="white_delta"', ...
    '$1source="white_delta" target="none"', "once");
graphmlFile = writeGraphml(root, "reversed_edge.graphml", xml);

result = convert(graphmlFile, files);
linkType = result.Allocations.LinkType(result.Allocations.EdgeId == "e6");

verifyEqual(testCase, linkType, "consumption");
end

function testDirtyLoadedModelIsPreserved(testCase)
[~, files] = newWorkspace(testCase, "Dirty");
model = systemcomposer.createModel(files.LogicalName);
save_system(files.LogicalName, files.LogicalPath);
model.Architecture.addComponent("UnsavedOnly");

call = @() convert(testCase.TestData.GraphmlFile, files);
verifyError(testCase, call, "opm2systemcomposer:UnsavedModelChanges");
verifyTrue(testCase, bdIsLoaded(files.LogicalName));
verifyEqual(testCase, string(get_param(files.LogicalName, "Dirty")), "on");
verifyEqual(testCase, ...
    string({model.Architecture.Components.Name}), "UnsavedOnly");
verifyFalse(testCase, isfile(files.FunctionalPath));
end

function testUnrelatedLoadedModelIsNotClosed(testCase)
[root, files] = newWorkspace(testCase, "Conflict");
otherFolder = fullfile(root, "other");
mkdir(otherFolder);
systemcomposer.createModel(files.LogicalName);
otherPath = fullfile(otherFolder, files.LogicalName + ".slx");
save_system(files.LogicalName, otherPath);

call = @() convert(testCase.TestData.GraphmlFile, files);
verifyError(testCase, call, "opm2systemcomposer:LoadedModelConflict");
verifyTrue(testCase, bdIsLoaded(files.LogicalName));
verifyEqual(testCase, string(get_param(files.LogicalName, "FileName")), otherPath);
verifyFalse(testCase, isfile(files.FunctionalPath));
end

function testOverwriteCanReplaceCleanLoadedOutputs(testCase)
[~, files] = newWorkspace(testCase, "Overwrite");
first = convert(testCase.TestData.GraphmlFile, files); %#ok<NASGU>

second = convert(testCase.TestData.GraphmlFile, files);

verifyEqual(testCase, ...
    numel(second.AllocationSet.Scenarios(1).Allocations), 12);
end

function testFailedOverwriteRestoresPreviousOutput(testCase)
assumeTrue(testCase, ispc);
[root, files] = newWorkspace(testCase, "Rollback");

original = systemcomposer.createModel(files.FunctionalName);
original.Architecture.addComponent("OriginalSentinel");
save_system(files.FunctionalName, files.FunctionalPath);
close_system(files.FunctionalName, 0);
files.LogicalName = "CON";
files.LogicalPath = fullfile(root, "CON.slx");

didFail = false;
try
    convert(testCase.TestData.GraphmlFile, files);
catch
    didFail = true;
end

verifyTrue(testCase, didFail);
verifyTrue(testCase, isfile(files.FunctionalPath));
verifyFalse(testCase, isfile(files.LogicalPath));
verifyFalse(testCase, isfile(files.AllocationPath));
load_system(files.FunctionalPath);
restored = systemcomposer.loadModel(files.FunctionalName);
verifyEqual(testCase, ...
    string({restored.Architecture.Components.Name}), "OriginalSentinel");
end

function result = convert(graphmlFile, files)
result = opm2systemcomposer(graphmlFile, ...
    FunctionalModelFile=files.FunctionalPath, ...
    LogicalModelFile=files.LogicalPath, ...
    AllocationSetFile=files.AllocationPath, ...
    Overwrite=true, Open=false);
end

function [root, files] = newWorkspace(testCase, prefix)
root = string(tempname);
mkdir(root);
[~, token] = fileparts(root);
token = string(matlab.lang.makeValidName(token));

files.FunctionalName = prefix + "Functions_" + token;
files.LogicalName = prefix + "Components_" + token;
files.AllocationName = prefix + "Allocation_" + token;
files.FunctionalPath = fullfile(root, files.FunctionalName + ".slx");
files.LogicalPath = fullfile(root, files.LogicalName + ".slx");
files.AllocationPath = fullfile(root, files.AllocationName + ".mldatx");

testCase.addTeardown(@cleanupArtifacts, root, ...
    [files.FunctionalName, files.LogicalName], files.AllocationName);
end

function graphmlFile = writeGraphml(root, name, text)
graphmlFile = fullfile(root, name);
file = fopen(graphmlFile, "w");
if file == -1
    error("test_opm2systemcomposer:FileOpenFailed", ...
        "Could not create GraphML fixture %s.", graphmlFile);
end
closeFile = onCleanup(@() fclose(file));
fwrite(file, text, "char");
end

function cleanupArtifacts(root, modelNames, allocationName)
openSet = systemcomposer.allocation.AllocationSet.find(allocationName);
if ~isempty(openSet)
    openSet.close(true);
end
loaded = string(find_system("type", "block_diagram"));
for name = modelNames
    if any(loaded == name)
        close_system(name, 0);
    end
end
if isfolder(root)
    rmdir(root, "s");
end
end
