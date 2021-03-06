function varargout = MVCTdose(varargin)
% The TomoTherapy MVCT Dose Calculator is a GUI based standalone 
% application written in MATLAB that parses TomoTherapy patient archives 
% and DICOM CT/RTSS files and calculates the dose to the CT given a set of
% MVCT delivery parameters.  The results are displayed and available for
% export.
%
% TomoTherapy is a registered trademark of Accuray Incorporated. See the
% README for more information, including installation information and
% algorithm details.
%
% Author: Mark Geurts, mark.w.geurts@gmail.com
% Copyright (C) 2015 University of Wisconsin Board of Regents
%
% This program is free software: you can redistribute it and/or modify it 
% under the terms of the GNU General Public License as published by the  
% Free Software Foundation, either version 3 of the License, or (at your 
% option) any later version.
%
% This program is distributed in the hope that it will be useful, but 
% WITHOUT ANY WARRANTY; without even the implied warranty of 
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General 
% Public License for more details.
% 
% You should have received a copy of the GNU General Public License along 
% with this program. If not, see http://www.gnu.org/licenses/.

% Last Modified by GUIDE v2.5 26-Dec-2014 20:35:40

% Begin initialization code - DO NOT EDIT
gui_Singleton = 0;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @MVCTdose_OpeningFcn, ...
                   'gui_OutputFcn',  @MVCTdose_OutputFcn, ...
                   'gui_LayoutFcn',  [] , ...
                   'gui_Callback',   []);
if nargin && ischar(varargin{1})
    gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function MVCTdose_OpeningFcn(hObject, ~, handles, varargin)
% This function has no output args, see OutputFcn.
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% varargin   command line arguments to MVCTdose (see VARARGIN)

% Turn off MATLAB warnings
warning('off', 'all');

% Choose default command line output for MVCTdose
handles.output = hObject;

% Set version handle
handles.version = '1.0.0';

% Determine path of current application
[path, ~, ~] = fileparts(mfilename('fullpath'));

% Set current directory to location of this application
cd(path);

% Clear temporary variable
clear path;

%% Initialize log
% Set version information.  See LoadVersionInfo for more details.
handles.versionInfo = LoadVersionInfo;

% Store program and MATLAB/etc version information as a string cell array
string = {'TomoTherapy MVCT Dose Calculator'
    sprintf('Version: %s (%s)', handles.version, handles.versionInfo{6});
    sprintf('Author: Mark Geurts <mark.w.geurts@gmail.com>');
    sprintf('MATLAB Version: %s', handles.versionInfo{2});
    sprintf('MATLAB License Number: %s', handles.versionInfo{3});
    sprintf('Operating System: %s', handles.versionInfo{1});
    sprintf('CUDA: %s', handles.versionInfo{4});
    sprintf('Java Version: %s', handles.versionInfo{5})
};

% Add dashed line separators      
separator = repmat('-', 1,  size(char(string), 2));
string = sprintf('%s\n', separator, string{:}, separator);

% Log information
Event(string, 'INIT');

%% Add Tomo archive extraction tools submodule
% Add archive extraction tools submodule to search path
addpath('./tomo_extract');

% Check if MATLAB can find CalcDose.m
if exist('CalcDose', 'file') ~= 2
    
    % If not, throw an error
    Event(['The Archive Extraction Tools submodule does not exist in the ', ...
        'search path. Use git clone --recursive or git submodule init ', ...
        'followed by git submodule update to fetch all submodules'], ...
        'ERROR');
end

%% Add DICOM tools submodule
% Add DICOM tools submodule to search path
addpath('./dicom_tools');

% Check if MATLAB can find LoadDICOMImages.m
if exist('LoadDICOMImages', 'file') ~= 2
    
    % If not, throw an error
    Event(['The DICOM Tools submodule does not exist in the ', ...
        'search path. Use git clone --recursive or git submodule init ', ...
        'followed by git submodule update to fetch all submodules'], ...
        'ERROR');
end

%% Add Structure Atlas submodule
% Add structure atlas submodule to search path
addpath('./structure_atlas');

% Check if MATLAB can find LoadDICOMImages.m
if exist('LoadAtlas', 'file') ~= 2
    
    % If not, throw an error
    Event(['The Structure Atlas submodule does not exist in the ', ...
        'search path. Use git clone --recursive or git submodule init ', ...
        'followed by git submodule update to fetch all submodules'], ...
        'ERROR');
end

%% Load beam models
% Declare path to beam model folders
handles.modeldir = './GPU';

% Initialize beam models cell array
handles.beammodels = {'Select AOM'};

% Search for folder list in beam model folder
Event(sprintf('Searching %s for beam models', handles.modeldir));
dirs = dir(handles.modeldir);

% Loop through results
for i = 1:length(dirs)
    
    % If the result is not a directory, skip
    if strcmp(dirs(i).name, '.') || strcmp(dirs(i).name, '..') || ...
            dirs(i).isdir == 0
        continue;
    else
       
        % Check for beam model files
        if exist(fullfile(handles.modeldir, dirs(i).name, 'dcom.header'), ...
                'file') == 2 && exist(fullfile(handles.modeldir, ...
                dirs(i).name, 'fat.img'), 'file') == 2 && ...
                exist(fullfile(handles.modeldir, dirs(i).name, ...
                'kernel.img'), 'file') == 2 && ...
                exist(fullfile(handles.modeldir, dirs(i).name, 'lft.img'), ...
                'file') == 2 && exist(fullfile(handles.modeldir, ...
                dirs(i).name, 'penumbra.img'), 'file') == 2
            
            % Log name
            Event(sprintf('Beam model %s verified', dirs(i).name));
            
            % If found, add the folder name to the beam models cell array
            handles.beammodels{length(handles.beammodels)+1} = dirs(i).name;
        else
            
            % Otherwise log why folder was excluded
            Event(sprintf(['Folder %s excluded as it does not contain all', ...
                ' required beam model files'], dirs(i).name), 'WARN');
        end
    end
end

% Log total number of beam models found
Event(sprintf('%i beam models found', length(handles.beammodels) - 1));

% Clear temporary variables
clear dirs i;

%% Configure Dose Calculation
% Check for presence of dose calculator
handles.calcDose = CalcDose();

% Set sadose flag
handles.sadose = 0;

% If calc dose was successful and sadose flag is set
if handles.calcDose == 1 && handles.sadose == 1
    
    % Log dose calculation status
    Event('CPU Dose calculation enabled');
    
% If calc dose was successful and sadose flag is not set
elseif handles.calcDose == 1 && handles.sadose == 0
    
    % Log dose calculation status
    Event('GPU Dose calculation enabled');
   
% Otherwise, calc dose was not successful
else
    
    % Log dose calculation status
    Event('Dose calculation disabled', 'WARN');
end

%% Load the default IVDT
% Log start
Event('Loading default IVDT');

% Open read file handle to default ivdt file
fid = fopen('ivdt.txt', 'r');

% If a valid file handle is returned
if fid > 2
    
    % Retrieve first line
    tline = fgetl(fid);
    
    % Match CT numbers
    s = strsplit(tline, '=');
    ctNums = textscan(s{2}, '%f');
    
    % Retrieve second line
    tline = fgetl(fid);
    
    % Match density values
    s = strsplit(tline, '=');
    densVals = textscan(s{2}, '%f');
    
    % Verify CT numbers and values were found
    if ~isempty(ctNums) && ~isempty(densVals)
        
        % Verify lengths match
        if length(ctNums{1}) ~= length(densVals{1})
            Event('Default IVDT vector length mismatch', 'ERROR');
        
        % Verify at least two elements exist
        elseif length(ctNums{1}) < 2
            Event('Default IVDT does not contain enough values', 'ERROR');
            
        % Verify the first CT number value is zero
        elseif ctNums{1}(1) ~= 0
            Event('Default IVDT first CT number must equal zero', 'ERROR');
            
        % Otherwise, set IVDT table
        else
            
            % Initialize ivdt temp cell array
            ivdt = cell(length(ctNums{1}) + 1, 2);
            
            % Loop through elements, writing formatted values
            for i = 1:length(ctNums{1})
                
                % Save formatted numbers
                ivdt{i,1} = sprintf('%0.0f', ctNums{1}(i) - 1024);
                ivdt{i,2} = sprintf('%g', densVals{1}(i));
                
            end
            
            % Set UI table contents
            set(handles.ivdt_table, 'Data', ivdt);
            
            % Log completion
            Event(sprintf(['Default IVDT loaded successfully with %i ', ...
                'elements'], length(ctNums{1})));
        end
    else
        % Otherwise, throw an error
        Event('Default IVDT file is not formatted correctly', 'ERROR');
    end
    
    % Close file handle
    fclose(fid);
    
else
    % Otherwise, throw error as default IVDT is missing
    Event('Default IVDT file is missing', 'ERROR');
end

% Clear temporary variables
clear fid tline s ctNums densVals ivdt i;

%% Initialize UI and declare global variables
% Initialize data variables
handles = clear_results_Callback(handles.clear_results, '', handles);

% Default folder path when selecting input files
handles.path = userpath;
Event(['Default file path set to ', handles.path]);

% Set version UI text
set(handles.version_text, 'String', sprintf('Version %s', handles.version));

% Set beam model menu
set(handles.beam_menu, 'String', handles.beammodels);

% If only one beam model exists, set and auto-populate results
if length(handles.beammodels) == 2
    set(handles.beam_menu, 'Value', 2);
else
    set(handles.beam_menu, 'Value', 1);
end

% Declare pitch options. An equal array of pitch values must also exist, 
% defined next. The options represent the menu options, the values are 
% couch rates in cm/rot  
handles.pitchoptions = {
    'Fine'
    'Normal'
    'Coarse'
};
handles.pitchvalues = [
    0.4
    0.8
    1.2
];
Event(['Pitch options set to: ', strjoin(handles.pitchoptions, ', ')]);

% Declare default period
handles.defaultperiod = 10;
Event(sprintf('Default period set to %0.1f sec', handles.defaultperiod));

% Set pitch menu options
set(handles.pitch_menu, 'String', vertcat('Select', handles.pitchoptions));

% Default MLC sinogram to all open
set(handles.mlc_radio_a, 'Value', 1);
    
% Set beam parameters (will also disable calc button)
handles = beam_menu_Callback(handles.beam_menu, '', handles);

% Set the initial image view orientation to Transverse (T)
handles.tcsview = 'T';
Event('Default dose view set to Transverse');

% Set the default transparency
set(handles.alpha, 'String', '40%');
Event(['Default dose view transparency set to ', ...
    get(handles.alpha, 'String')]);

% Attempt to load the atlas
handles.atlas = LoadAtlas('structure_atlas/atlas.xml');

% Report initilization status
Event(['Initialization completed successfully. Start by selecting a ', ...
    'patient archive or DICOM CT image set.']);

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function varargout = MVCTdose_OutputFcn(~, ~, handles) 
% varargout  cell array for returning output args (see VARARGOUT);
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Get default command line output from handles structure
varargout{1} = handles.output;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function image_file_Callback(~, ~, ~)
% hObject    handle to image_file (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function image_file_CreateFcn(hObject, ~, ~)
% hObject    handle to image_file (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), ...
        get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function image_browse_Callback(hObject, ~, handles)
% hObject    handle to image_browse (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Log event
Event('Image browse button selected');

% Request the user to select the image DICOM or XML
Event('UI window opened to select file');
[name, path] = uigetfile({'*.dcm', 'CT Image Files (*.dcm)'; ...
    '*_patient.xml', 'Patient Archive (*.xml)'}, ...
    'Select the Image Files', handles.path, 'MultiSelect', 'on');

% If a file was selected
if iscell(name) || sum(name ~= 0)
    
    % Update default path
    handles.path = path;
    Event(['Default file path updated to ', path]);
    
    % If not cell array, cast as one
    if ~iscell(name)
        
        % Update text box with file name
        set(handles.image_file, 'String', fullfile(path, name));
        names{1} = name;
        
    else
        % Update text box with first file
        set(handles.image_file, 'String', path);
        names = name;
    end
    
    % Disable DVH table
    set(handles.dvh_table, 'Visible', 'off');

    % Disable dose and DVH axes
    set(allchild(handles.dose_axes), 'visible', 'off'); 
    set(handles.dose_axes, 'visible', 'off');
    colorbar(handles.dose_axes, 'off');
    set(allchild(handles.dvh_axes), 'visible', 'off'); 
    set(handles.dvh_axes, 'visible', 'off');

    % Hide dose slider/TCS/alpha
    set(handles.dose_slider, 'visible', 'off');
    set(handles.tcs_button, 'visible', 'off');
    set(handles.alpha, 'visible', 'off');

    % Disable export buttons
    set(handles.dose_button, 'Enable', 'off');
    set(handles.dvh_button, 'Enable', 'off');

    % Search for an xml extension
    s = regexpi(names{1}, '.xml$');

    % If .xml was not found, use DICOM to load image    
    if isempty(s) 
        
        % Load DICOM images
        handles.image = LoadDICOMImages(path, names);
        
        % Enable structure set browse
        set(handles.struct_file, 'Enable', 'on');        
        set(handles.struct_browse, 'Enable', 'on');
        
        % If current structure set FOR UID does not match image
        if isfield(handles, 'structures') && ~isempty(handles.structures) ...
                && (~isfield(handles.structures{1}, 'frameRefUID') || ...
                ~strcmp(handles.structures{1}.frameRefUID, ...
                handles.image.frameRefUID))
                
            % Log event
            Event(['Existing structure data cleared as it no longer ', ...
                'matches loaded image set'], 'WARN');

            % Clear structures
            handles.structures = [];

            % Clear structures file
            set(handles.struct_file, 'String', ''); 
        end
    else
        
        % Start waitbar
        progress = waitbar(0, 'Loading patient archive');
        
        % Search for plans and MVCT scan lengths
        scans = FindMVCTScanLengths(path, names{1});
        
        % Update progress bar
        waitbar(0.3, progress);
        
        % If no plans were found
        if isempty(scans)
            
            % Log event
            Event('No plans were found in selected patient archive', ...
                'ERROR');
            
        % Otherwise, if one plan was found
        elseif length(scans) == 1
            
            % Select only plan
            s(1) = 1;
            
        % Otherwise, if more than one plan was found
        elseif length(scans) > 1
            
            % Prompt user to select plan
            Event('Opening UI for user to select image set');
            n = cell2mat(scans);
            [s, v] = listdlg('PromptString', ...
                'Multiple plans were found. Select a plan to load:', ...
                'SelectionMode', 'single', 'ListString', {n.planName}, ...
                'ListSize', [300 100]);
            
            % If no plan was selected, throw an error
            if v == 0
                Event('No plan is selected', 'ERROR');
            end
            
            % Clear temporary variable
            clear v n;
        end
        
        % Load image 
        handles.image = LoadImage(path, names{1}, ...
            scans{s(1)}.planUID);
        
        % Update progress bar
        waitbar(0.6, progress);
        
        % Load plan (for isocenter position)
        handles.plan = LoadPlan(path, names{1}, scans{s(1)}.planUID);
        
        % Update progress bar
        waitbar(0.7, progress);
        
        % Load structure set
        handles.structures = LoadStructures(path, names{1}, ...
            handles.image, handles.atlas);
        
        % Update progress bar
        waitbar(0.9, progress);
        
        % Initialize slice menu
        Event(sprintf('Loading %i scans to slice selection menu', ...
            length(scans{s(1)}.scanLengths)));
        handles.slices = cell(1, length(scans{s(1)}.scanLengths)+1);
        handles.slices{1} = 'Manual slice selection';
        
        % Loop through scan lengths
        for i = 1:length(scans{s(1)}.scanLengths)
            handles.slices{i+1} = sprintf('%i. [%g %g] %s-%s', i, ...
                scans{s(1)}.scanLengths(i,:) + handles.image.isocenter(3), ...
                scans{s(1)}.date{i}, scans{s(1)}.time{i});
        end
        
        % Update slice selection menu UI
        set(handles.slice_menu, 'String', handles.slices);
        set(handles.slice_menu, 'Value', 1);
        
        % Initialize ivdt temp cell array
        Event('Updating IVDT table from patient archive');
        ivdt = cell(size(handles.image.ivdt, 1) + 1, 2);

        % Loop through elements, writing formatted values
        for i = 1:size(handles.image.ivdt, 1)

            % Save formatted numbers
            ivdt{i,1} = sprintf('%0.0f', handles.image.ivdt(i,1) - 1024);
            ivdt{i,2} = sprintf('%g', handles.image.ivdt(i, 2));

        end
        
        % Set IVDT table
        set(handles.ivdt_table, 'Data', ivdt);
        
        % Clear temporary variables
        clear scans s i ivdt;
        
        % Update waitbar
        waitbar(1.0, progress, 'Patient archive loading completed');
        
        % Initialize DVH table
        set(handles.dvh_table, 'Data', ...
            InitializeStatistics(handles.structures));
        
        % Clear and disable structure set browse
        set(handles.struct_file, 'String', '');
        set(handles.struct_file, 'Enable', 'off');        
        set(handles.struct_browse, 'Enable', 'off');
        
        % Close waitbar
        close(progress);
        
        % Clear temporary variables
        clear progress;
    end
    
    % Delete slice selector if one exists
    if isfield(handles, 'selector')
        
        % Log deletion
        Event('Deleting old slice selector');
        
        % Retrieve current handle
        api = iptgetapi(handles.selector);
        
        % If a valid handle is returned, delete it
        if ~isempty(api); api.delete(); end
        
        % Clear temporary variable
        clear api;
    end
    
    % Set slice to center of dataset
    slice = floor(handles.image.dimensions(1)/2);
    
    % Extract sagittal slice through center of image
    imageA = squeeze(handles.image.data(slice, :, :));
    
    % Set image widths
    width = [handles.image.width(3) handles.image.width(2)];
    
    % Set image start values
    start = [handles.image.start(3) handles.image.start(2)];
    
    % Plot sagittal plane in slice selector
    axes(handles.slice_axes);
    
    % Create reference object based on the start and width inputs
    reference = imref2d(size(imageA), [start(1) start(1) + size(imageA,2) * ...
        width(1)], [start(2) start(2) + size(imageA,1) * width(2)]);
    
    % Display the reference image
    imshow(ind2rgb(gray2ind((imageA) / 2048, 64), colormap('gray')), ...
            reference);
    
    % Add image contours
    if isfield(handles, 'structures') && ~isempty(handles.structures)
        
        % Hold the axes to allow overlapping contours
        hold on;
        
        % Retrieve dvh data
        stats = get(handles.dvh_table, 'Data');
        
        % Loop through each structure
        for i = 1:length(handles.structures)
            
            % If the statistics display column for this structure is set to
            % true (checked)
            if stats{i, 2}
                
                % Use bwboundaries to generate X/Y contour points based
                % on structure mask
                B = bwboundaries(squeeze(...
                    handles.structures{i}.mask(slice, :, :))');
            
                % Loop through each contour set (typically this is one)
                for k = 1:length(B)
                    
                    % Plot the contour points given the structure color
                    plot((B{k}(:,1) - 1) * width(1) + start(1), ...
                        (B{k}(:,2) - 1) * width(2) + start(2), ...
                       'Color', handles.structures{i}.color/255, ...
                       'LineWidth', 2);
                end
            end
        end
        
        % Unhold axes generation
        hold off;
    end
    
    % Show the slice selection plot
    set(handles.slice_axes, 'visible', 'on');

    % Hide the x/y axis on the images
    axis off;
    
    % Disallow zoom on slice selector
    h = zoom;
    setAllowAxesZoom(h, handles.slice_axes, false);

    % Create interactive slice selector line to allow user to select slice 
    % ranges, defaulting to all slices
    handles.selector = imdistline(handles.slice_axes, ...
        [start(1) start(1) + size(imageA, 2) * width(1)], ...
        [0 0]);

    % Retrieve handle to slice selector API
    api = iptgetapi(handles.selector);
    
    % Constrain line to only resize horizontally, and only to the upper and
    % lower extent of the image using drag constraint function
    fcn = @(pos) [max(start(1), min(pos(:,1))) 0; ...
            min(start(1) + size(imageA, 2) * width(1), max(pos(:,1))) 0];
    api.setDragConstraintFcn(fcn);
    
    % Hide distance label
    api.setLabelVisible(0);
    
    % Clear temporary variable
    clear h s i j k name names path sag width start reference slice B ...
        imageA fcn api;
    
    % Log completion of slice selection load
    Event(['Slice selector initialized. Drag the endpoints of the slice', ...
        'selector to adjust the MVCT scan length.']);
    
% Otherwise no file was selected
else
    Event('No files were selected');
end

% Verify new data
handles = checkCalculateInputs(handles);

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function struct_file_Callback(~, ~, ~)
% hObject    handle to struct_file (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function struct_file_CreateFcn(hObject, ~, ~)
% hObject    handle to struct_file (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), ...
        get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function struct_browse_Callback(hObject, ~, handles)
% hObject    handle to struct_browse (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Log event
Event('Structure browse button selected');

% Request the user to select the structure set DICOM
Event('UI window opened to select file');
[name, path] = uigetfile({'*.dcm', 'RTSS Files (*.dcm)'}, ...
    'Select the Structure Set', handles.path, 'MultiSelect', 'off');

% If the user selected a file, and appropriate inputs are present
if ~isequal(name, 0) && isfield(handles, 'image') && ...
        isfield(handles, 'atlas')
    
    % Update text box with file name
    set(handles.struct_file, 'String', fullfile(path, name));
    
    % Update default path
    handles.path = path;
    Event(['Default file path updated to ', path]);
    
    % Disable DVH table
    set(handles.dvh_table, 'Visible', 'off');

    % Disable dose and DVH axes
    set(allchild(handles.dose_axes), 'visible', 'off'); 
    set(handles.dose_axes, 'visible', 'off');
    colorbar(handles.dose_axes, 'off');
    set(allchild(handles.dvh_axes), 'visible', 'off'); 
    set(handles.dvh_axes, 'visible', 'off');

    % Hide dose slider/TCS/alpha
    set(handles.dose_slider, 'visible', 'off');
    set(handles.tcs_button, 'visible', 'off');
    set(handles.alpha, 'visible', 'off');

    % Disable export buttons
    set(handles.dose_button, 'Enable', 'off');
    set(handles.dvh_button, 'Enable', 'off');
    
    % Load DICOM structure set
    handles.structures = LoadDICOMStructures(path, name, handles.image, ...
        handles.atlas);
    
    % Initialize DVH table
    set(handles.dvh_table, 'Data', ...
        InitializeStatistics(handles.structures, handles.atlas));
    
    % Add image contours, if image data already exists
    if isfield(handles, 'image') && isfield(handles.image, 'data') && ...
            size(handles.image.data, 3) > 0
        
        % Retrieve current handle
        api = iptgetapi(handles.selector);
 
        % Retrieve current values
        pos = api.getPosition();
        
        % Set slice to center of dataset
        slice = floor(handles.image.dimensions(1)/2);
    
        % Extract sagittal slice through center of image
        imageA = squeeze(handles.image.data(slice, :, :));

        % Set image widths
        width = [handles.image.width(3) handles.image.width(2)];

        % Set image start values
        start = [handles.image.start(3) handles.image.start(2)];

        % Plot sagittal plane in slice selector
        axes(handles.slice_axes);

        % Create reference object based on the start and width inputs
        reference = imref2d(size(imageA), [start(1) start(1) + ...
            size(imageA,2) * width(1)], [start(2) start(2) + ...
            size(imageA,1) * width(2)]);

        % Display the reference image
        imshow(ind2rgb(gray2ind((imageA) / 2048, 64), colormap('gray')), ...
                reference);
        
        % Hold the axes to allow overlapping contours
        hold on;
        
        % Retrieve dvh data
        stats = get(handles.dvh_table, 'Data');
        
        % Loop through each structure
        for i = 1:length(handles.structures)
            
            % If the statistics display column for this structure is set to
            % true (checked)
            if stats{i, 2}
                
                % Use bwboundaries to generate X/Y contour points based
                % on structure mask
                B = bwboundaries(squeeze(...
                    handles.structures{i}.mask(slice, :, :))');
            
                % Loop through each contour set (typically this is one)
                for k = 1:length(B)
                    
                    % Plot the contour points given the structure color
                    plot((B{k}(:,1) - 1) * width(1) + start(1), ...
                        (B{k}(:,2) - 1) * width(2) + start(2), ...
                       'Color', handles.structures{i}.color/255, ...
                       'LineWidth', 2);
                end
            end
        end
        
        % Unhold axes generation
        hold off;
        
        % Hide the x/y axis on the images
        axis off;
        
        % Disallow zoom on slice selector
        h = zoom;
        setAllowAxesZoom(h, handles.slice_axes, false);
        
        % Create interactive slice selector line to allow user to select  
        % slice ranges, defaulting to all slices
        handles.selector = imdistline(handles.slice_axes, pos(:,1), ...
            pos(:,2));

        % Retrieve handle to slice selector API
        api = iptgetapi(handles.selector);

        % Constrain line to only resize horizontally, and only to the upper 
        % and lower extent of the image using drag constraint function
        fcn = @(pos) [max(start(1), min(pos(:,1))) 0; ...
            min(start(1) + size(imageA, 2) * width(1), max(pos(:,1))) 0];
        api.setDragConstraintFcn(fcn);
        
        % Hide distance label
        api.setLabelVisible(0);

        % Clear temporary variables
        clear h slice width start stats i B k fcn api pos;
    end
    
% Otherwise no file was selected
else
    Event('No file was selected, or supporting data is not present');
end

% Verify new data
handles = checkCalculateInputs(handles);

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function slice_menu_Callback(hObject, ~, handles) %#ok<*DEFNU>
% hObject    handle to slice_menu (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% If user selected a procedure
if get(hObject, 'Value') > 1
    
    % Retrieve positions from slice menu
    val = cell2mat(textscan(...
        handles.slices{get(hObject, 'Value')}, '%f [%f %f] %f-%f'));
    
    % Log event
    Event(sprintf('Updating slice selector to [%g %g]', val(2:3)));
    
    % Retrieve handle to slice selector API
    api = iptgetapi(handles.selector);
    
    % Get current handle position
    pos = api.getPosition();

    % Update start and end values
    pos(1,1) = val(2);
    pos(2,1) = val(3);
    
    % Update slice selector
    api.setPosition(pos);
    
    % Clear temporary variables
    clear val pos api;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function slice_menu_CreateFcn(hObject, ~, ~)
% hObject    handle to slice_menu (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), ...
        get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function varargout = beam_menu_Callback(hObject, ~, handles)
% hObject    handle to beam_menu (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Clear and disable beam output
set(handles.beamoutput, 'String', '');
set(handles.beamoutput, 'Enable', 'off');
set(handles.text9, 'Enable', 'off');

% Clear and disable gantry period
set(handles.period, 'String', '');
set(handles.period, 'Enable', 'off');
set(handles.text13, 'Enable', 'off');

% Clear and disable jaw settings
set(handles.jaw, 'String', '');
set(handles.jaw, 'Enable', 'off');
set(handles.jaw_menu, 'String', 'Select');
set(handles.jaw_menu, 'Value', 1);
set(handles.jaw_menu, 'Enable', 'off');
set(handles.text20, 'Enable', 'off');

% Disable pitch 
set(handles.pitch, 'Enable', 'off');
set(handles.pitch_menu, 'Enable', 'off');
set(handles.text18, 'Enable', 'off');

% Disable MLC parameters
set(handles.mlc_radio_a, 'Enable', 'off');
set(handles.mlc_radio_b, 'Enable', 'off');

% Disable custom sinogram inputs
set(handles.sino_file, 'Enable', 'off');
set(handles.sino_browse, 'Enable', 'off');
set(handles.projection_rate, 'Enable', 'off');
set(handles.text16, 'Enable', 'off');
set(handles.text17, 'Enable', 'off');

% Disable sinogram axes
set(allchild(handles.sino_axes), 'visible', 'off'); 
set(handles.sino_axes, 'visible', 'off');

% Initialize field size array
handles.fieldsizes = [];
    
% If current value is greater than 1 (beam model selected)
if get(hObject, 'Value') > 1
    
    % Initialize penumbras array
    penumbras = [];
    
    % Open file handle to dcom.header
    fid = fopen(fullfile(handles.modeldir, ...
        handles.beammodels{get(hObject, 'Value')}, 'dcom.header'), 'r');
    
    % If fopen was successful
    if fid > 2
        
        % Retrieve first line
        tline = fgetl(fid);
        
        % While data exists
        while ischar(tline)
        
            % If the line is efiot
            match = ...
                regexpi(tline, 'dcom.efiot[ =]+([0-9\.e\+-]+)', 'tokens');
            if ~isempty(match)
                
                % Set the beam output
                set(handles.beamoutput, 'String', sprintf('%0.4e', ...
                    str2double(match{1})));
                Event(sprintf('Beam output set to %0.4e MeV-cm2/sec', ...
                    str2double(match{1})));
            end
            
            % If the line is penumbra x counts
            match = regexpi(tline, ['dcom.penumbra.header.([0-9]+).', ...
                'xCount[ =]+([0-9]+)'], 'tokens');
            if ~isempty(match)
                
                % Store the x counts
                penumbras(str2double(match{1}(1))+1, 1) = ...
                    str2double(match{1}(2)); %#ok<*AGROW>
            end
            
            % If the line is penumbra z counts
            match = regexpi(tline, ['dcom.penumbra.header.([0-9]+).', ...
                'zCount[ =]+([0-9]+)'], 'tokens');
            if ~isempty(match)
                
                % Store the z counts
                penumbras(str2double(match{1}(1))+1, 2) = ...
                    str2double(match{1}(2));
            end
                
            % Retrieve next line
            tline = fgetl(fid);
        end
        
        % Close file
        fclose(fid);
     
    % Otherwise, throw an error
    else
        Event(sprintf('Error opening %s', fullfile(handles.modeldir, ...
            handles.beammodels{get(hObject, 'Value')}, 'dcom.header')), ...
            'ERROR');
    end
    
    % Open a file handle to penumbra.img
    fid = fopen(fullfile(handles.modeldir, ...
        handles.beammodels{get(hObject, 'Value')}, 'penumbra.img'), ...
        'r', 'l');
    
    % If fopen was successful
    if fid > 2
        
        % Loop through the penumbras
        for i = 1:size(penumbras,1)
            
            % Read in the ith penumbra filter
            arr = reshape(fread(fid, prod(penumbras(i,:) + 1), 'single'), ...
                penumbras(i,:) + 1);
            
            % Store field size
            handles.fieldsizes(i) = arr(1,1);
            
        end
        
        % Reshape field size array and multiply by 85 cm
        handles.fieldsizes = reshape(handles.fieldsizes, [], 2) * 85;
        
    % Otherwise, throw an error
    else
        Event(sprintf('Error opening %s', fullfile(handles.modeldir, ...
            handles.beammodels{get(hObject, 'Value')}, 'penumbra.img')), ...
            'ERROR');
    end
    
    % Initialize menu cell array
    menu = cell(1, size(handles.fieldsizes, 1));
    
    % Loop through field sizes
    for i = 1:size(handles.fieldsizes, 1)
        
        % Store field size in [back, front] format
        menu{i} = sprintf('[%0.2g %0.2g]', handles.fieldsizes(i, :));
        
        % Log field size
        Event(sprintf('Commissioned field size [%0.2g %0.2g] loaded', ...
            handles.fieldsizes(i, :)));
    end
    
    % Set field size options
    set(handles.jaw_menu, 'String', horzcat('Select', menu));
    
    % Enable beam output
    set(handles.beamoutput, 'Enable', 'on');
    set(handles.text9, 'Enable', 'on');
    
    % Enable gantry period
    set(handles.period, 'String', sprintf('%0.1f', handles.defaultperiod));
    set(handles.period, 'Enable', 'on');
    Event(sprintf('Gantry period set to %0.1f sec', handles.defaultperiod));
    set(handles.text13, 'Enable', 'on');

    % Enable jaw settings
    set(handles.jaw_menu, 'Enable', 'on');
    set(handles.jaw, 'Enable', 'on');
    set(handles.text20, 'Enable', 'on');

    % Enable pitch settings
    set(handles.pitch_menu, 'Enable', 'on');
    set(handles.pitch, 'Enable', 'on');
    set(handles.text18, 'Enable', 'on');

    % Enable MLC parameters
    set(handles.mlc_radio_a, 'Enable', 'on');
    set(handles.mlc_radio_b, 'Enable', 'on');

    % If custom sinogram is selected
    if get(handles.mlc_radio_b, 'Value') == 1
        
        % Enable custom sinogram inputs
        set(handles.sino_file, 'Enable', 'on');
        set(handles.sino_browse, 'Enable', 'on');
        set(handles.projection_rate, 'Enable', 'on');
        set(handles.text16, 'Enable', 'on');
        set(handles.text17, 'Enable', 'on');

    end
    
    % If custom sinogram is loaded
    if isfield(handles, 'sinogram') && ~isempty(handles.sinogram)
        
        % Enable sinogram axes
        set(allchild(handles.sino_axes), 'visible', 'on'); 
        set(handles.sino_axes, 'visible', 'on');
    end
    
    % Clear temporary variables
    clear fid i tline match penumbras arr menu;
    
end

% Verify new data
handles = checkCalculateInputs(handles);

% If called through the UI, and not another function
if nargout == 0
    
    % Update handles structure
    guidata(hObject, handles);
    
else
    
    % Otherwise return the modified handles
    varargout{1} = handles;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function beam_menu_CreateFcn(hObject, ~, ~)
% hObject    handle to beam_menu (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), ...
        get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function beamoutput_Callback(hObject, ~, handles)
% hObject    handle to beamoutput (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Parse value to number
set(hObject, 'String', sprintf('%g', str2double(get(hObject, 'String'))));

% Verify new data
handles = checkCalculateInputs(handles);

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function beamoutput_CreateFcn(hObject, ~, ~)
% hObject    handle to beamoutput (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), ...
        get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function jaw_text_Callback(hObject, ~, handles)
% hObject    handle to jaw (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Verify new data
handles = checkCalculateInputs(handles);

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function jaw_text_CreateFcn(hObject, ~, ~)
% hObject    handle to jaw (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), ...
        get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function period_Callback(hObject, ~, handles)
% hObject    handle to period (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Parse value to number
set(hObject, 'String', sprintf('%g', str2double(get(hObject, 'String'))));

% Verify new data
handles = checkCalculateInputs(handles);

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function period_CreateFcn(hObject, ~, ~)
% hObject    handle to period (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), ...
        get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function pitch_Callback(hObject, ~, handles)
% hObject    handle to pitch (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Parse value to number
set(hObject, 'String', sprintf('%g', str2double(get(hObject, 'String'))));

% Verify new data
handles = checkCalculateInputs(handles);

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function pitch_CreateFcn(hObject, ~, ~)
% hObject    handle to pitch (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), ...
        get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function pitch_menu_Callback(hObject, ~, handles)
% hObject    handle to pitch_menu (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% If a valid pitch has been selected
if get(hObject, 'Value') > 1
    
    % Log event
    Event(sprintf('Pitch changed to %s (%0.1f cm/rot)', ...
        handles.pitchoptions{get(hObject, 'Value') - 1}, ...
        handles.pitchvalues(get(hObject, 'Value') - 1)));

    % Set pitch value
    set(handles.pitch, 'String', sprintf('%0.1f', ...
        handles.pitchvalues(get(hObject, 'Value') - 1)));
end

% Verify new data
handles = checkCalculateInputs(handles);

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function pitch_menu_CreateFcn(hObject, ~, ~)
% hObject    handle to pitch_menu (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), ...
        get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function mlc_radio_a_Callback(hObject, ~, handles)
% hObject    handle to mlc_radio_a (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Log event
Event('MLC sinogram set to all open');

% Disable custom option
set(handles.mlc_radio_b, 'Value', 0);

% Disable custom sinogram inputs
set(handles.sino_file, 'Enable', 'off');
set(handles.sino_browse, 'Enable', 'off');
set(handles.projection_rate, 'Enable', 'off');
set(handles.text16, 'Enable', 'off');
set(handles.text17, 'Enable', 'off');

% Disable sinogram axes
set(allchild(handles.sino_axes), 'visible', 'off'); 
set(handles.sino_axes, 'visible', 'off');

% Verify new data
handles = checkCalculateInputs(handles);

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function mlc_radio_b_Callback(hObject, ~, handles)
% hObject    handle to mlc_radio_b (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Log event
Event('MLC sinogram set to custom');

% Disable allopen option
set(handles.mlc_radio_a, 'Value', 0);

% Enable custom sinogram inputs
set(handles.sino_file, 'Enable', 'on');
set(handles.sino_browse, 'Enable', 'on');
set(handles.projection_rate, 'Enable', 'on');
set(handles.text16, 'Enable', 'on');
set(handles.text17, 'Enable', 'on');
    
% If custom sinogram is loaded
if isfield(handles, 'sinogram') && ~isempty(handles.sinogram)

    % Enable sinogram axes
    set(allchild(handles.sino_axes), 'visible', 'on'); 
    set(handles.sino_axes, 'visible', 'on');
end
    
% Verify new data
handles = checkCalculateInputs(handles);

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function sino_file_Callback(~, ~, ~)
% hObject    handle to sino_file (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function sino_file_CreateFcn(hObject, ~, ~)
% hObject    handle to sino_file (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), ...
        get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function sino_browse_Callback(hObject, ~, handles)
% hObject    handle to sino_browse (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Log event
Event('Sinogram browse button selected');

% Request the user to select the sinogram file
Event('UI window opened to select file');
[name, path] = uigetfile('*.*', 'Select a sinogram binary file', ...
    handles.path);

% If the user selected a file
if ~isequal(name, 0)
    
    % Clear existing sinogram data
    handles.sinogram = [];
    
    % Update default path
    handles.path = path;
    Event(['Default file path updated to ', path]);
    
    % Update sino_file text box
    set(handles.sino_file, 'String', fullfile(path, name));
    
    % Extract file contents
    handles.sinogram = LoadSinogram(path, name); 
    
    % Log plot
    Event('Plotting sinogram');
    
    % Plot sinogram
    axes(handles.sino_axes);
    imagesc(handles.sinogram');
    colormap(handles.sino_axes, 'default');
    colorbar;
    
    % Enable sinogram axes
    set(allchild(handles.sino_axes), 'visible', 'on'); 
    set(handles.sino_axes, 'visible', 'on');

else
    % Log event
    Event('No file was selected');
end

% Clear temporary variables
clear name path ax;

% Verify new data
handles = checkCalculateInputs(handles);

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function projection_rate_Callback(hObject, ~, handles)
% hObject    handle to projection_rate (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Parse value to number
set(hObject, 'String', sprintf('%g', str2double(get(hObject, 'String'))));

% Verify new data
handles = checkCalculateInputs(handles);

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function projection_rate_CreateFcn(hObject, ~, ~)
% hObject    handle to projection_rate (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), ...
        get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function dose_slider_Callback(hObject, ~, handles)
% hObject    handle to dose_slider (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Round the current value to an integer value
set(hObject, 'Value', round(get(hObject, 'Value')));

% Log event
Event(sprintf('Dose viewer slice set to %i', get(hObject,'Value')));

% Update viewer with current slice and transparency value
UpdateViewer(get(hObject,'Value'), ...
    sscanf(get(handles.alpha, 'String'), '%f%%')/100);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function dose_slider_CreateFcn(hObject, ~, ~)
% hObject    handle to dose_slider (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: slider controls usually have a light gray background.
if isequal(get(hObject,'BackgroundColor'), ...
        get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor',[.9 .9 .9]);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function alpha_Callback(hObject, ~, handles)
% hObject    handle to alpha (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% If the string contains a '%', parse the value
if ~isempty(strfind(get(hObject, 'String'), '%'))
    value = sscanf(get(hObject, 'String'), '%f%%');
    
% Otherwise, attempt to parse the response as a number
else
    value = str2double(get(hObject, 'String'));
end

% Bound value to [0 100]
value = max(0, min(100, value));

% Log event
Event(sprintf('Dose transparency set to %0.0f%%', value));

% Update string with formatted value
set(hObject, 'String', sprintf('%0.0f%%', value));

% Update viewer with current slice and transparency value
UpdateViewer(get(handles.dose_slider,'Value'), value/100);

% Clear temporary variable
clear value;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function alpha_CreateFcn(hObject, ~, ~)
% hObject    handle to alpha (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), ...
        get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function tcs_button_Callback(hObject, ~, handles)
% hObject    handle to tcs_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Based on current tcsview handle value
switch handles.tcsview
    
    % If current view is transverse
    case 'T'
        handles.tcsview = 'C';
        Event('Updating viewer to Coronal');
        
    % If current view is coronal
    case 'C'
        handles.tcsview = 'S';
        Event('Updating viewer to Sagittal');
        
    % If current view is sagittal
    case 'S'
        handles.tcsview = 'T';
        Event('Updating viewer to Transverse');
end

% Re-initialize image viewer with new T/C/S value
InitializeViewer(handles.dose_axes, handles.tcsview, ...
    sscanf(get(handles.alpha, 'String'), '%f%%')/100, handles.image, ...
    handles.dose, handles.dose_slider);

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function dvh_button_Callback(~, ~, handles)
% hObject    handle to dvh_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Log event
Event('DVH export button selected');

% Prompt user to select save location
Event('UI window opened to select save file location');
[name, path] = uiputfile('*.csv', 'Save DVH As');

% If the user provided a file location
if ~isequal(name, 0) && isfield(handles, 'image') && ...
        isfield(handles, 'structures') && isfield(handles, 'dose')
    
    % Store structures to image variable
    handles.image.structures = handles.structures;
    
    % Execute WriteDVH
    WriteDVH(handles.image, handles.dose, fullfile(path, name));
    
% Otherwise no file was selected
else
    Event('No file was selected, or supporting data is not present');
end

% Clear temporary variables
clear name path;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function dose_button_Callback(~, ~, handles)
% hObject    handle to dose_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Log event
Event('Dose export button selected');

% Prompt user to select save location
Event('UI window opened to select save file location');
[name, path] = uiputfile('*.dcm', 'Save Dose As');

% If the user provided a file location
if ~isequal(name, 0) && isfield(handles, 'image') && ...
        isfield(handles, 'structures') && isfield(handles, 'dose')
    
    % Store structures to image variable
    handles.image.structures = handles.structures;
    
    % Set series description 
    handles.image.seriesDescription = 'TomoTherapy MVCT Calculated Dose';
    
    % Execute WriteDICOMDose
    WriteDICOMDose(handles.dose, fullfile(path, name), handles.image);
    
% Otherwise no file was selected
else
    Event('No file was selected, or supporting data is not present');
end

% Clear temporary variables
clear name path;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function jaw_menu_Callback(hObject, ~, handles)
% hObject    handle to jaw_menu (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% If a valid pitch has been selected
if get(hObject, 'Value') > 1
    
    % Log event
    Event(sprintf('Field size changed to [%0.2g %0.2g] (%0.2g cm)', ...
        handles.fieldsizes(get(hObject, 'Value') - 1, :), ...
        sum(abs(handles.fieldsizes(get(hObject, 'Value') - 1, :)))));

    % Set field size value
    set(handles.jaw, 'String', sprintf('%0.2g', ...
        sum(abs(handles.fieldsizes(get(hObject, 'Value') - 1, :)))));
    
    % Verify new data
    handles = checkCalculateInputs(handles);
end

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function jaw_menu_CreateFcn(hObject, ~, ~)
% hObject    handle to jaw_menu (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), ...
        get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function jaw_Callback(hObject, ~, handles)
% hObject    handle to jaw (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Parse value to number
set(hObject, 'String', sprintf('%g', str2double(get(hObject, 'String'))));

% Verify new data
handles = checkCalculateInputs(handles);

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function jaw_CreateFcn(hObject, ~, ~)
% hObject    handle to jaw (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), ...
        get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function calc_button_Callback(hObject, ~, handles)
% hObject    handle to calc_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Log event
Event('Calculate dose button pressed');

% Start waitbar
progress = waitbar(0, 'Calculating dose');

%% Disable results
% Disable DVH table
set(handles.dvh_table, 'Visible', 'off');

% Disable dose and DVH axes
set(allchild(handles.dose_axes), 'visible', 'off'); 
set(handles.dose_axes, 'visible', 'off');
colorbar(handles.dose_axes, 'off');
set(allchild(handles.dvh_axes), 'visible', 'off'); 
set(handles.dvh_axes, 'visible', 'off');

% Hide dose slider/TCS/alpha
set(handles.dose_slider, 'visible', 'off');
set(handles.tcs_button, 'visible', 'off');
set(handles.alpha, 'visible', 'off');

% Disable export buttons
set(handles.dose_button, 'Enable', 'off');
set(handles.dvh_button, 'Enable', 'off');

%% Create Image Input
% Retrieve IVDT data
Event('Retrieving IVDT data');
ivdt = str2double(get(handles.ivdt_table, 'Data'));

% Remove empty values
ivdt(any(isnan(ivdt), 2),:) = [];

% Convert HU values back to CT numbers
ivdt(:,1) = ivdt(:,1) + 1024;

% Store ivdt data to image structure
handles.image.ivdt = ivdt;

% Update progress bar
waitbar(0.05, progress);

%% Create Plan Input
% Initialize plan structure
Event(['Generating delivery plan from slice selection and beam model', ...
    ' inputs']);
plan = struct;

% If a custom sinogram was loaded
if get(handles.mlc_radio_b, 'Value') == 1

    % Set plan scale (sec/tau) to inverse of projection rate (tau/sec)
    plan.scale = 1 / str2double(get(handles.projection_rate, 'String'));
    
% Otherwise, use an all open sinogram
else
    
    % Assume scale is 1 second/tau
    plan.scale = 1;
    
end

% Log scale
Event(sprintf('Plan scale set to %g sec/tau', plan.scale));

% Initialize plan.events array with sync event. Events that do not have a 
% value are given the placeholder value 1.7976931348623157E308 
plan.events{1,1} = 0;
plan.events{1,2} = 'sync';
plan.events{1,3} = 1.7976931348623157E308;

% Add a projection width event at tau = 0
k = size(plan.events, 1) + 1;
plan.events{k,1} = 0;
plan.events{k,2} = 'projWidth';
plan.events{k,3} = 1;

% Add isoX and isoY
k = size(plan.events, 1) + 1;

% If plan is loaded
if isfield(handles, 'plan') && isfield(handles.plan, 'isocenter')
    
    % Set isocenter X/Y from delivery plan
    plan.events{k,1} = 0;
    plan.events{k,2} = 'isoX';
    plan.events{k,3} = handles.plan.isocenter(1);
    plan.events{k+1,1} = 0;
    plan.events{k+1,2} = 'isoY';
    plan.events{k+1,3} = handles.plan.isocenter(2);

% Otherwise, if image contains isocenter tag
elseif isfield(handles.image, 'isocenter') 
    
    % Set isocenter X/Y from image reference isocenter
    plan.events{k,1} = 0;
    plan.events{k,2} = 'isoX';
    plan.events{k,3} = handles.image.isocenter(1);
    plan.events{k+1,1} = 0;
    plan.events{k+1,2} = 'isoY';
    plan.events{k+1,3} = handles.image.isocenter(2);
    
% Otherwise set to 0,0 (DICOM isocenter)
else
    plan.events{k,1} = 0;
    plan.events{k,2} = 'isoX';
    plan.events{k,3} = 0;
    plan.events{k+1,1} = 0;
    plan.events{k+1,2} = 'isoY';
    plan.events{k+1,3} = 0;
end

% Update progress bar
waitbar(0.1, progress);

% Retrieve slice selector handle
api = iptgetapi(handles.selector);

% If a valid handle is not returned
if isempty(api)

    % Throw an error
    Event('No slice selector found', 'ERROR');

% Otherwise, a valid handle is returned
else

    % Retrieve current values
    pos = api.getPosition();

end

% Add isoZ (cm) based on superior slice selection position
Event(sprintf('MVCT scan start position set to %g cm', max(pos(1,1), ...
    pos(2,1))));
k = size(plan.events, 1) + 1;
plan.events{k,1} = 0;
plan.events{k,2} = 'isoZ';
plan.events{k,3} = min(pos(1,1), pos(2,1));

% Update progress bar
waitbar(0.15, progress);

% Add isoXRate and isoYRate as 0 cm/tau
k = size(plan.events, 1) + 1;
plan.events{k,1} = 0;
plan.events{k,2} = 'isoXRate';
plan.events{k,3} = 0;
plan.events{k+1,1} = 0;
plan.events{k+1,2} = 'isoYRate';
plan.events{k+1,3} = 0;

% Add isoZRate (cm/tau) as pitch (cm/rot) / GP (sec/rot) * scale (sec/tau)
Event(sprintf('Couch velocity set to %g cm/sec', ...
    str2double(get(handles.pitch, 'String')) / ...
    str2double(get(handles.period, 'String'))));
k = size(plan.events, 1) + 1;
plan.events{k,1} = 0;
plan.events{k,2} = 'isoZRate';
plan.events{k,3} = str2double(get(handles.pitch, 'String')) / ...
    str2double(get(handles.period, 'String')) * plan.scale;

% Add jawBack and jawFront based on UI value, assuming beam is symmetric
% about isocenter (in cm at isocenter divided by SAD)
Event(sprintf('Jaw positions set to [-%g %g]', ...
    str2double(get(handles.jaw, 'String')) / (85 * 2), ...
    str2double(get(handles.jaw, 'String')) / (85 * 2)));
k = size(plan.events, 1) + 1;
plan.events{k,1} = 0;
plan.events{k,2} = 'jawBack';
plan.events{k,3} = -str2double(get(handles.jaw, 'String')) / (85 * 2);
plan.events{k+1,1} = 0;
plan.events{k+1,2} = 'jawFront';
plan.events{k+1,3} = str2double(get(handles.jaw, 'String')) / (85 * 2);

% Add jawBackRate and jawFrontRate as 0 (no jaw motion)
k = size(plan.events, 1) + 1;
plan.events{k,1} = 0;
plan.events{k,2} = 'jawBackRate';
plan.events{k,3} = 0;
plan.events{k+1,1} = 0;
plan.events{k+1,2} = 'jawFrontRate';
plan.events{k+1,3} = 0;

% Add start angle as 0 deg
k = size(plan.events, 1) + 1;
plan.events{k,1} = 0;
plan.events{k,2} = 'gantryAngle';
plan.events{k,3} = 0;

% Add gantry rate (deg/tau) based on 360 (deg/rot) / UI value (sec/rot) *
% scale (sec/tau)
Event(sprintf('Gantry rate set to %g deg/sec', 360 / ...
    str2double(get(handles.period, 'String'))));
k = size(plan.events, 1) + 1;
plan.events{k,1} = 0;
plan.events{k,2} = 'gantryRate';
plan.events{k,3} = 360 / str2double(get(handles.period, 'String')) * ...
    plan.scale;

% Determine total number of projections based on couch travel distance (cm)
% / pitch (cm/rot) * GP (sec/rot) / scale (sec/tau)
totalTau = abs(pos(2,1) - pos(1,1)) / ...
    str2double(get(handles.pitch, 'String')) * ...
    str2double(get(handles.period, 'String')) / plan.scale;
Event(sprintf('End of Procedure set to %g projections', totalTau));

% Add unsync and eop events at final tau value. These events do not have a 
% value, so use the placeholder
k = size(plan.events,1)+1;
plan.events{k,1} = totalTau;
plan.events{k,2} = 'unsync';
plan.events{k,3} = 1.7976931348623157E308;
plan.events{k+1,1} = totalTau;
plan.events{k+1,2} = 'eop';
plan.events{k+1,3} = 1.7976931348623157E308;

% Set lowerLeafIndex plan variable
Event('Lower Leaf Index set to 0');
plan.lowerLeafIndex = 0;

% Set numberOfLeaves
Event('Number of Leaves set to 64');
plan.numberOfLeaves = 64;

% Set numberOfProjections to next whole integer
Event(sprintf('Number of Projections set to %i', ceil(totalTau)));
plan.numberOfProjections = ceil(totalTau);

% Set startTrim and stopTrim
Event(sprintf('Start and stop trim set to 1 and %i', ceil(totalTau)));
plan.startTrim = 1;
plan.stopTrim = ceil(totalTau);

% If a custom sinogram was loaded
if get(handles.mlc_radio_b, 'Value') == 1

    % If custom sinogram is less than what is needed
    if size(handles.sinogram, 2) < ceil(totalTau)
        
        % Warn user that additional closed projections will be used
        Event(sprintf(['Custom sinogram is shorter than need by %i ', ...
            'projections, and will be extended with all closed leaves'], ...
            ceil(totalTau) - size(handles.sinogram, 2)), 'WARN');
        
        % Initialize empty plan sinogram
        plan.sinogram = zeros(64, plan.numberOfProjections);
        
        % Fill with custom sinogram
        plan.sinogram(:, 1:size(handles.sinogram, 2)) = handles.sinogram;
        
    % Otherwise, if custom sinogram is larger
    elseif size(handles.sinogram, 2) > ceil(totalTau)
        
        % Warn user that not all of sinogram will be used
        Event(sprintf(['Custom sinogram is larger than need by %i ', ...
            'projections, which will be discarded for dose calculation'], ...
            size(handles.sinogram, 2) - ceil(totalTau)), 'WARN');
        
        % Fill with custom sinogram
        plan.sinogram = handles.sinogram(:, 1:ceil(totalTau));
    
    % Otherwise, it is just right
    else
        % Inform the user
        Event('Custom sinogram is just right!');
        
        % Fill with custom sinogram
        plan.sinogram = handles.sinogram;
    end
    
% Otherwise, use an all open sinogram
else
    Event('Generating all open leaves sinogram');
    plan.sinogram = ones(64, plan.numberOfProjections);
end

% Update progress bar
waitbar(0.2, progress);

%% Write beam model to temporary directory
% Generate temporary folder
folder = tempname;
[status, cmdout] = system(['mkdir ', folder]);
if status > 0
    Event(['Error occurred creating temporary directory: ', cmdout], ...
        'ERROR');
end

% Copy beam model files to temporary directory
Event(['Copying beam model files from ', fullfile(handles.modeldir, ...
    handles.beammodels{get(handles.beam_menu, 'Value')}), '/ to ', folder]);
[status, cmdout] = system(['cp ', fullfile(handles.modeldir, ...
    handles.beammodels{get(handles.beam_menu, 'Value')}, '*.*'), ...
    ' ', folder, '/']);

% If status is 0, cp was successful.  Otherwise, log error
if status > 0
    Event(['Error occurred copying beam model files to temporary ', ...
        'directory: ', cmdout], 'ERROR');
end

% Clear temporary variables
clear status cmdout;

% Update progress bar
waitbar(0.25, progress);

% Open read handle to beam model dcom.header
fidr = fopen(fullfile(handles.modeldir, handles.beammodels{get(...
    handles.beam_menu, 'Value')}, 'dcom.header'), 'r');

% Open write handle to temporary dcom.header
Event('Editing dcom.header to specify output');
fidw = fopen(fullfile(folder, 'dcom.header'), 'w');

% If either file handles are invalid, throw an error
if fidr < 3 || fidw < 3
    Event('A file handle could not be opened to dcom.header', 'ERROR');
end

% Retrieve the first line from dcom.header
tline = fgetl(fidr);

% While data exists
while ischar(tline)
    
    % If line contains beam output
    if ~isempty(regexpi(tline, 'dcom.efiot'))
        
        % Write custom beam output based on UI value
        fprintf(fidw, 'dcom.efiot = %g\n', ...
            str2double(get(handles.beamoutput, 'String')));
        
    % Otherwise, write tline back to temp file
    else
        fprintf(fidw, '%s\n', tline);
    end
    
    % Retrieve the next line
    tline = fgetl(fidr);
end

% Close file handles
fclose(fidr);
fclose(fidw);

% Update progress bar
waitbar(0.3, progress);

%% Calculate and display dose
% Calculate dose using image, plan, directory, & sadose flag
handles.dose = CalcDose(handles.image, plan, folder, handles.sadose);

% If dose was computed
if isfield(handles.dose, 'data')

    % Update progress bar
    waitbar(0.7, progress, 'Updating results');

    % Clear temporary variables
    clear ivdt plan k folder fidr fidw tline api pos totalTau;

    % Clear and set reference to axis
    cla(handles.dose_axes, 'reset');
    axes(handles.dose_axes);
    Event('Plotting dose image');

    % Enable Image Viewer UI components
    set(allchild(handles.dose_axes), 'visible', 'on'); 
    set(handles.dose_axes, 'visible', 'on');
    set(handles.dose_slider, 'visible', 'on');
    set(handles.tcs_button, 'visible', 'on'); 
    set(handles.alpha, 'visible', 'on');

    % Add necessary fields to image and dose variables
    handles.image.structures = handles.structures;
    handles.image.stats = get(handles.dvh_table, 'Data');
    handles.dose.registration = [];

    % Initialize image viewer
    InitializeViewer(handles.dose_axes, handles.tcsview, ...
        sscanf(get(handles.alpha, 'String'), '%f%%')/100, handles.image, ...
        handles.dose, handles.dose_slider);

    % Update progress bar
    waitbar(0.8, progress);

    % If structures are present
    if isfield(handles, 'structures') && ~isempty(handles.structures)

        % Update DVH plot
        handles.dose.dvh = UpdateDVH(handles.dvh_axes, ...
            get(handles.dvh_table, 'Data'), handles.image, handles.dose);

        % Update progress bar
        waitbar(0.9, progress);

        % Update Dx/Vx statistics
        set(handles.dvh_table, 'Data', UpdateDoseStatistics(...
            get(handles.dvh_table, 'Data'), [], handles.dose.dvh));

        % Enable statistics table
        set(handles.dvh_table, 'Visible', 'on');

        % Enable DVH export button
        set(handles.dvh_button, 'Enable', 'on');
    end

    % Update progress bar
    waitbar(1.0, progress, 'Dose calculation completed');

    % Enable dose export buttons
    set(handles.dose_button, 'Enable', 'on');
end

% Close and delete progress handle
close(progress);
clear progress;

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function dvh_table_CellEditCallback(hObject, eventdata, handles)
% hObject    handle to dvh_table (see GCBO)
% eventdata  structure with the following fields 
%       (see MATLAB.UI.CONTROL.TABLE)
%	Indices: row and column indices of the cell(s) edited
%	PreviousData: previous data for the cell(s) edited
%	EditData: string(s) entered by the user
%	NewData: EditData or its converted form set on the Data property. Empty 
%       if Data was not changed
%	Error: error string when failed to convert EditData to appropriate 
%       value for Data
% handles    structure with handles and user data (see GUIDATA)

% Get current data
stats = get(hObject, 'Data');

% Verify edited Dx value is a number or empty
if eventdata.Indices(2) == 3 && isnan(str2double(...
        stats{eventdata.Indices(1), eventdata.Indices(2)})) && ...
        ~isempty(stats{eventdata.Indices(1), eventdata.Indices(2)})
    
    % Warn user
    Event(sprintf(['Dx value "%s" is not a number, reverting to previous ', ...
        'value'], stats{eventdata.Indices(1), eventdata.Indices(2)}), 'WARN');
    
    % Revert value to previous
    stats{eventdata.Indices(1), eventdata.Indices(2)} = ...
        eventdata.PreviousData;

% Otherwise, if Dx was changed
elseif eventdata.Indices(2) == 3
    
    % Update edited Dx/Vx statistic
    stats = UpdateDoseStatistics(stats, eventdata.Indices);

% Otherwise, if display value was changed
elseif eventdata.Indices(2) == 2
    
    % Update dose plot if it is displayed
    if strcmp(get(handles.dose_slider, 'visible'), 'on')

        % Update dose plot
        UpdateViewer(get(handles.dose_slider,'Value'), ...
            sscanf(get(handles.alpha, 'String'), '%f%%')/100, stats);
    end

    % Update DVH plot if it is displayed
    if strcmp(get(handles.dvh_axes, 'visible'), 'on')
        
        % Update DVH plot
        UpdateDVH(stats); 
    end
end

% Set new table data
set(hObject, 'Data', stats);

% Clear temporary variable
clear stats;

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function ivdt_table_CellEditCallback(hObject, eventdata, handles)
% hObject    handle to ivdt_table (see GCBO)
% eventdata  structure with the following fields (see 
%       MATLAB.UI.CONTROL.TABLE)
%	Indices: row and column indices of the cell(s) edited
%	PreviousData: previous data for the cell(s) edited
%	EditData: string(s) entered by the user
%	NewData: EditData or its converted form set on the Data property. Empty 
%       if Data was not changed
%	Error: error string when failed to convert EditData to appropriate 
%       value for Data
% handles    structure with handles and user data (see GUIDATA)

% Retrieve current data array
ivdt = get(hObject, 'Data');

% Verify edited value is a number or empty
if isnan(str2double(ivdt{eventdata.Indices(1), eventdata.Indices(2)})) && ...
        ~isempty(ivdt{eventdata.Indices(1), eventdata.Indices(2)})
    
    % Warn user
    Event(sprintf(['IVDT value "%s" is not a number, reverting to previous ', ...
        'value'], ivdt{eventdata.Indices(1), eventdata.Indices(2)}), 'WARN');
    
    % Revert value to previous
    ivdt{eventdata.Indices(1), eventdata.Indices(2)} = ...
        eventdata.PreviousData;

% If an HU value was edited, round to nearest integer
elseif eventdata.Indices(2) == 1 && round(str2double(ivdt{eventdata.Indices(1), ...
        eventdata.Indices(2)})) ~= str2double(ivdt{eventdata.Indices(1), ...
        eventdata.Indices(2)}) && ...
        ~isempty(ivdt{eventdata.Indices(1), eventdata.Indices(2)})
    
    % Log round to nearest integer
    Event(sprintf('HU value %s rounded to an integer', ...
        ivdt{eventdata.Indices(1), eventdata.Indices(2)}), 'WARN');
    
    % Store rounded value
    ivdt{eventdata.Indices(1), eventdata.Indices(2)} = sprintf('%0.0f', ...
        str2double(ivdt{eventdata.Indices(1), eventdata.Indices(2)}));

% If a density value was edited, convert to number
elseif eventdata.Indices(2) == 1 && ...
        ~isempty(ivdt{eventdata.Indices(1), eventdata.Indices(2)})
    
    % Store number
    ivdt{eventdata.Indices(1), eventdata.Indices(2)} = sprintf('%g', ...
        str2double(ivdt{eventdata.Indices(1), eventdata.Indices(2)}));
    
end

% If HU values were changed and results are not sorted
if eventdata.Indices(2) == 1 && ~issorted(str2double(ivdt), 'rows')
    
    % Log event
    Event('Resorting IVDT array');
    
    % Retrieve sort indices
    [~,I] = sort(str2double(ivdt), 1, 'ascend');
    
    % Store sorted ivdt array
    ivdt = ivdt(I(:,1),:);
    
end

% If the edited cell was the last row, add a new empty row
if size(ivdt,1) == eventdata.Indices(1)
    ivdt{size(ivdt,1)+1, 1} = [];
end

% Set formatted/sorted IVDT data
set(hObject, 'Data', ivdt);

% Verify new data
handles = checkCalculateInputs(handles);

% Update handles structure
guidata(hObject, handles);

% Clear temporary variables
clear ivdt I;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function handles = checkCalculateInputs(handles)
% checkCalculateInputs checks to see if all dose calculation inputs have
% been set, and if so, enables the "Calculate Dose" button

% Initialize disable flag and reason string
disable = false;
reason = '';

%% Verify data variables are set
% Verify CT data exists
if ~isfield(handles, 'image') || ~isfield(handles.image, 'data') || ...
        length(size(handles.image.data)) ~= 3
    
    reason = 'image data does not exist';
    disable = true;
    
% Verify slice selector exists
elseif ~isfield(handles, 'selector')
    
    reason = 'no slice selector found';
    disable = true;
    
% Verify IVDT table data exists
elseif size(get(handles.ivdt_table, 'Data'), 1) < 2
    
    reason = 'no IVDT data exists';
    disable = true;
    
% Verify beam output exists and is greater than 0
elseif isnan(str2double(get(handles.beamoutput, 'String'))) || ...
        str2double(get(handles.beamoutput, 'String')) <= 0
    
    reason = 'beam output is not valid';
    disable = true;

% Verify gantry period exists and is greater than 0
elseif isnan(str2double(get(handles.period, 'String'))) || ...
        str2double(get(handles.period, 'String')) <= 0
    
    reason = 'gantry period is not valid';
    disable = true;

% Verify field width exists and is greater than 0
elseif isnan(str2double(get(handles.jaw, 'String'))) || ...
        str2double(get(handles.jaw, 'String')) <= 0
    
    reason = 'field width is not valid';
    disable = true;
    
% Verify pitch exists and is greater than 0
elseif isnan(str2double(get(handles.pitch, 'String'))) || ...
        str2double(get(handles.pitch, 'String')) <= 0
    
    reason = 'pitch is not valid';
    disable = true;
end

%% Verify IVDT values
% Convert IVDT values to numbers
ivdt = str2double(get(handles.ivdt_table, 'Data'));

% Verify first HU value is -1024
if ivdt(1,1) ~= -1024
    
    reason = 'the first IVDT entry must define density at -1024';
    disable = true;
   
% Verify the HU values are sorted
elseif ~issorted(ivdt(:, 1))
    
    reason = 'the IVDT HU values must be in ascending order';
    disable = true;

% Verify the density values are sorted
elseif ~issorted(ivdt(:, 2))
    
    reason = 'the IVDT density values must be in ascending order';
    disable = true;
    
% Verify at least two HU values exist
elseif length(ivdt(:, 1)) - sum(isnan(ivdt(:, 1))) <= 2
    
    reason = 'the IVDT must contain at least two values';
    disable = true;
    
% Verify the number of non-zero HU and density values are equal
elseif length(ivdt(:, 1)) - sum(isnan(ivdt(:, 1))) ~= ...
        length(ivdt(:, 2)) - sum(isnan(ivdt(:, 2)))
    
    reason = 'the number of IVDT HU and density values must be equal';
    disable = true;
end

%% Verify slice selection values
if ~disable && isfield(handles, 'selector') 
    
    % Retrieve current handle
    api = iptgetapi(handles.selector);

    % If a valid handle is not returned
    if isempty(api)
        
        % Disable calculation
        reason = 'no slice selector found';
        disable = true; 

    % Otherwise, a valid handle is returned
    else
        
        % Retrieve current values
        pos = api.getPosition();
        
        % If current values are not within slice boundaries
        if pos(1,1) < handles.image.start(3) || pos(2,1) > ...
                handles.image.start(3) + size(handles.image.data, 3) * ...
                handles.image.width(3)
            
            % Disable calculation
            reason = 'slice selector is not within image boundaries';
            disable = true;
            
        end
    end
end

%% Verify custom MLC values
% If a custom sinogram is selected
if get(handles.mlc_radio_b, 'Value') == 1
    
    % Verify sinogram data exists
    if ~isfield(handles, 'sinogram') || size(handles.sinogram, 1) == 0
        
        reason = 'custom sinogram is not loaded';
        disable = true;
    
    % Verify a projection rate exists and is greater than 0
    elseif isnan(str2double(get(handles.projection_rate, 'String'))) || ...
            str2double(get(handles.projection_rate, 'String')) <= 0
        
        reason = 'projection rate is not valid';
        disable = true;
    
    end
end

%% Finish verification
% If calcDose is set to 0, the calc server does not exist
if handles.calcDose == 0
    
    reason = 'no dose calculator was found';
    disable = true;

end

% If disable flag is still set
if disable
    
    % If previous state was enabled
    if strcmp(get(handles.calc_button, 'Enable'), 'on')
        
        % Log reason for changing status
        Event(['Dose calculation is disabled: ', reason], 'WARN');
        
    end
    
    % Disable calc button
    set(handles.calc_button, 'Enable', 'off');
    
else

    % If previous state was disabled
    if strcmp(get(handles.calc_button, 'Enable'), 'off')
        
        % Log reason for changing status
        Event('Dose calculation inputs passed validation checks');
        
    end
    
    % Enable calc button
    set(handles.calc_button, 'Enable', 'on');
    
end

% Clear temporary variables
clear reason pos ivdt;
    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function varargout = clear_results_Callback(hObject, ~, handles)
% hObject    handle to clear_results (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Log action
if isfield(handles, 'image')
    Event('Clearing all data variables from memory');
else
    Event('Initializing data variables');
end

% Clear image data
set(handles.image_file, 'String', '');  
handles.image = [];

% Clear and delete slice selector
if isfield(handles, 'selector') 
    
    % Retrieve current handle
    api = iptgetapi(handles.selector);

    % If a valid handle is returned, delete it
    if ~isempty(api); api.delete(); end

    % Clear temporary variable
    clear api;
end

% Clear slice selection list variable and update menu
handles.slices = {'Manual slice selection'};
set(handles.slice_menu, 'String', handles.slices);

% Clear and disable structure set browse
set(handles.struct_file, 'String', '');  
set(handles.struct_file, 'Enable', 'off');        
set(handles.struct_browse, 'Enable', 'off');
handles.structures = [];

% Clear stats table
set(handles.dvh_table, 'Data', cell(20, 4));

% Disable slice selection axes
set(allchild(handles.slice_axes), 'visible', 'off'); 
set(handles.slice_axes, 'visible', 'off');

% Disable calc button
set(handles.calc_button, 'Enable', 'off');

% Disable DVH table
set(handles.dvh_table, 'Visible', 'off');

% Disable dose and DVH axes
set(allchild(handles.dose_axes), 'visible', 'off'); 
set(handles.dose_axes, 'visible', 'off');
colorbar(handles.dose_axes, 'off');
set(allchild(handles.dvh_axes), 'visible', 'off'); 
set(handles.dvh_axes, 'visible', 'off');

% Hide dose slider/TCS/alpha
set(handles.dose_slider, 'visible', 'off');
set(handles.tcs_button, 'visible', 'off');
set(handles.alpha, 'visible', 'off');

% Disable export buttons
set(handles.dose_button, 'Enable', 'off');
set(handles.dvh_button, 'Enable', 'off');

% If called through the UI, and not another function
if nargout == 0
    
    % Update handles structure
    guidata(hObject, handles);
    
else
    
    % Otherwise return the modified handles
    varargout{1} = handles;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function figure1_SizeChangedFcn(hObject, ~, handles)
% hObject    handle to figure1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Set units to pixels
set(hObject, 'Units', 'pixels');

% Get table width
pos = get(handles.ivdt_table, 'Position') .* ...
    get(handles.uipanel8, 'Position') .* ...
    get(hObject, 'Position');

% Update column widths to scale to new table size
set(handles.ivdt_table, 'ColumnWidth', ...
    {floor(0.5*pos(3)) - 11 floor(0.5*pos(3)) - 11});

% Get table width
pos = get(handles.dvh_table, 'Position') .* ...
    get(handles.uipanel5, 'Position') .* ...
    get(hObject, 'Position');

% Update column widths to scale to new table size
set(handles.dvh_table, 'ColumnWidth', ...
    {floor(0.60*pos(3)) - 39 20 floor(0.2*pos(3)) ...
    floor(0.2*pos(3))});

% Clear temporary variables
clear pos;
