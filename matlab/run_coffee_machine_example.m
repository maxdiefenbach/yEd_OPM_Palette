%% OPM diagram -> System Composer: coffee machine example
% Converts graphml/testdata/coffee_machine.graphml (drawn with the
% yEd_OPM_Palette) into a functional architecture, a logical architecture
% and an allocation set between them. See README.md in this folder.

here = fileparts(mfilename("fullpath"));
graphmlFile = fullfile(here, "..", "graphml", "testdata", "coffee_machine.graphml");

% Output file names are optional; these are the defaults, written to out/.
outFolder = fullfile(here, "out");
result = opm2systemcomposer(graphmlFile, ...
    FunctionalModelFile=fullfile(outFolder, "FunctionalArchitecture.slx"), ...
    LogicalModelFile=fullfile(outFolder, "LogicalArchitecture.slx"), ...
    AllocationSetFile=fullfile(outFolder, "FunctionalToLogical.mldatx"), ...
    Overwrite=true);

%% What ended up where
disp(result.Processes)     % -> components of FunctionalArchitecture.slx
disp(result.Objects)       % -> components of LogicalArchitecture.slx
disp(result.Allocations)   % -> allocations in FunctionalToLogical.mldatx
disp(result.Files)         % full paths of the three generated files
