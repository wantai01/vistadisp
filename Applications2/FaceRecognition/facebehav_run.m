function stim = facebehav_run(scriptName, subject, varargin);
% Run a size/position face-recognition behavioral task.
%
%   stim = facebehav_run([scriptName='gender-1-1.txt'], [subject], [options]);
%
%
% This test evaluates how well subjects can perform different behavioral
% face discriminations (such as detection, categorization, gender
% discriminaion, and identification) for different face sizes and retinal
% positions.
%
%  The types of task supported include 'detect' (face versus
%  phase-scrambled face), 'categorize', (face versus nonface object),
%  'gender' (male versus female faces), and 'identify' (single target face
%  versus other faces). The image specification for these tasks is provided
%  in the separate function FACEBEHAV_MAKESCRIPT.
%
% INPUTS:
%   scriptName: name of image script (produced by FACEREC_MAKESCRIPT).
%
%   subject: optional subject name. If a name is provided, the behavioral
%   performance will be saved in the file code/Data/[filename.mat].
%
%   options: you can also specify 'Parameter Name', [value], ... argument
%   pairs to set other experimental parameters, such as the type of task,
%   whether to mask the images, etc. See the top of this function for the
%   set of parameters.
%
% OUTPUTS:
%   stim: stimulus struct.
%
%
% ras, 05/2009.
if notDefined('scriptName'), scriptName = 'gender-1-1.txt';        end
if notDefined('subject'),       subject = '';                              end

tic

%% params
stim.scriptName = scriptName;
stim.subject = subject;
stim.runCode = mfilename;
stim.date = datestr(now);
stim.contrast = .2;
stim.fixPos = [0 0]; % fixation position [X Y] relative to screen center (pixels)
stim.balanceLR = 1;  % flag to randomly L/R flip half the trials 
stim.screenRes = [1680 1050];
stim.displayName = prefsDisplayName;

% expected key responses for match and nonmatch stimuli
% (Note that '1' and '2' are for the KEYPAD, while '1!' and '2@' are for
% the number keys at the top of the keyboard):
stim.responseKeys = [KbName('1') KbName('2')];

% other fields
stim.runPriority = 7;
stim.startScan = 0;

%% read in the script
stim = facebehav_readscript(scriptName, stim);

%% parse the options
for ii = 1:2:length(varargin)
    stim.(varargin{ii}) = varargin{ii+1};
end

%% set the parameters for this display
stim.display = loadDisplayParams(prefsDisplayName);
stim.display.numPixels = stim.screenRes;
stim.display.backColorIndex = stim.bgColor;
stim.display.backColorRgb = [stim.bgColor stim.bgColor stim.bgColor 255];
stim.srcRect = [0 0 stim.display.numPixels];
stim.destRect = stim.srcRect;

stim.display.fixX = round(stim.screenRes(1)/2) + stim.fixPos(1);
stim.display.fixY = round(stim.screenRes(2)/2) + stim.fixPos(2);
stim.display.fixGrid = 0;
stim.display.fixSizePixels = 2;

stim.cmap = [gray(255); 1 0 0];

fprintf('[%s]: load time: %i min %2.1f sec.\n', mfilename, floor(toc/60), ...
		mod(toc, 60));

%% run the stimulus
stim = runStimulus(stim);

%% close up
stim = closeDisplay(stim, subject);


return
% /-----------------------------------------------------------------/ %




% /-----------------------------------------------------------------/ %
function stim = runStimulus(stim);
%% run the ABAB Color Stimulus, collecting user responses.
% This code is based off code in doRetinotopyScan.
% ras, 07/2008.

% loading mex functions for the first time can be
% extremely slow (seconds!), so we want to make sure that 
% the ones we are using are loaded.
KbCheck; GetSecs; WaitSecs(0.001);

% first, try to get devices (we can proceed if this doesn't work)
try
    stim.display.devices        = getDevices;
catch
    disp('Couldn''t find devices: won''t be able to get keyboard input.')
    stim.display.devices = [];
end

try,
    % check for OpenGL
    AssertOpenGL;
    
    % to skip annoying warning message on display (but not terminal)
    Screen('Preference','SkipSyncTests', 1);
    
    % Open the screen
    stim.display = openScreen(stim.display);

    % to allow blending
    Screen('BlendFunction', stim.display.windowPtr, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    
    % load the images
    stim = facebehav_loadImages(stim);
    
    % Store the images in textures
    stim = facebehav_createTextures(stim, 0);

    % set priority
    Priority(stim.runPriority);
    
    % wait for go signal
    if isequal( lower(stim.task), 'identify' )
        facebehav_showTarget(stim);
    else
        pressKey2Begin(stim.display, false, [], stim.taskStr);
    end
        
%     % put up a blank screen
%     Screen('DrawTexture', stim.display.windowPtr, stim.textures(stim.imgNum(2)));
%     drawFixation(stim.display, stim.fixSeq(1));
%     Screen('Flip', stim.display.windowPtr);
    
    % go
    time0 = getSecs;
    [response, timing, quitProg] = showColorStimulus(stim.display, stim, time0);
    
    % record responses
    stim.responses = response;
    
    % reset priority
    Priority(0);
    
    % report timing
    fprintf('Done. Total stimulus duration: %i min %2.1f sec. \n', ...
        floor((getSecs-time0)/60), mod((getSecs-time0), 60));
    
    % Close the one on-screen and many off-screen windows
    closeScreen(stim.display);
		
catch,
    % clean up if error occurred
    Screen('CloseAll');
    setGamma(0);
    Priority(0);
    ShowCursor;
    rethrow(lasterror);
	
end;

return
% /---------------------------------------------------------------------/ %




% /---------------------------------------------------------------------/ %
function stim = closeDisplay(stim, subject);
%% close the PsychToolbox display and finish up
closeScreen(stim.display);
Screen('CloseAll');
setGamma(0);
Priority(0);
ShowCursor;

% compute performance on the task 
try
    stim = computeTaskPerformance(stim);
catch
    warning('Couldn''t compute task performance.')
end

if ~isempty(subject)
    %% save the performance data
    [p f ext]= fileparts(stim.scriptName);
    condition = f(1:end-2);
    
    codeDir = fileparts( which(mfilename) );  % same directory as this code
    dataDir = fullfile(codeDir, 'Data');
    ensureDirExists(dataDir);
    
    % keeping the images makes the files very very large, and theyre
    % already on disk, so we don't need them here:
    fullRecord.images = {};
    
    fullFileName = fullfile(dataDir, [subject '_' condition '.mat']);
    if exist(fullFileName,'file')
        load(fullFileName);
        fullRecord = structAppend(stim, fullRecord);
    else
        fullRecord = stim;
    end
    
    save(fullFileName, 'fullRecord');
    fprintf('Saved scan parameters / subject performance in %s.\n', fullFileName);
end

return
% /---------------------------------------------------------------------/ %




% /---------------------------------------------------------------------/ %
function s = structAppend(newStruct, s);
% this function appends the struct newStruct onto the existing struct s,
% such that the result is a struct array, with newStruct being the last
% entry. It merges the fields of newStruct and s, so that if they don't
% perfectly match, it still returns a struct. (This would error if you
% tried "s(end+1) = newStruct;"

% initialize new entry
s(end+1) = s(end);

% manually set the defined fields from the new struct
for field = fieldnames(newStruct)'
    s(end).(field{1}) = newStruct.(field{1});
end
    
return
% /---------------------------------------------------------------------/ %




% /---------------------------------------------------------------------/ %
function stim = computeTaskPerformance(stim);
%% compute performance on the face recognition task for the just-completed
%% run.

%% extract only the behaviorally relevant events
% (we ignore 'blank' image offsets and end-of-run events)
ok = 3:2:length(stim.cond);
stim.responses.cond = stim.cond(ok);
stim.responses.image = stim.image(ok);
stim.responses.faceSize = stim.faceSize(ok);
stim.responses.faceEcc = stim.faceEcc(ok);
stim.responses.faceAngle = stim.faceAngle(ok);
stim.responses.isMatch = stim.isMatch(ok);
stim.responses.whichKey = stim.responses.keyCode(ok)';

% empirically derived: the 'isMatch' field is shifted by 1 event for some
% reason. We'll correct it here:
stim.responses.isMatch = circshift(stim.responses.isMatch(:), 1)';

%% for the 'whichKey' field, map from the key code for each guess to the
%% 'response index': that is, whether the pressed key indicated the subject
%% thought it was a match (1) or nonmatch (2).
responseIndex = zeros( size(stim.responses.cond) );
responseIndex( stim.responses.whichKey==stim.responseKeys(1) ) = 1;
responseIndex( stim.responses.whichKey==stim.responseKeys(2) ) = 2;

% let's also map keypresses for invalid keys: whichKey will be nonzero, but
% not be a member of either of the response keys:
invalid = find( stim.responses.whichKey > 0 & ...
                ~ismember(stim.responses.whichKey, stim.responseKeys) );
responseIndex(invalid) = -1;
if length(invalid) > 10
    warning('Subject pressed invalid key for >10 trials.')
end
    
    
stim.responses.responseIndex = responseIndex;

%% compute whether each trial was correct.
stim.responses.isCorrect = (responseIndex==stim.responses.isMatch);
stim.responses.percentCorrect = 100 * mean(stim.responses.isCorrect);

% for now, I will hard-code a loop across size and eccentricity. If I also
% test other dimensions, such as polar angle, I will need to modify this
% code
sizes = unique(stim.responses.faceSize);
ecc  = unique(stim.responses.faceEcc);
sizes = sizes( sizes > 0 );
ecc   = ecc( ecc >= 0 );
for s = 1:length(sizes)
    for e = 1:length(ecc)
        I = find(stim.responses.faceSize==sizes(s) & ...
                 stim.responses.faceEcc==ecc(e));
        stim.responses.pc(s,e) = mean( stim.responses.isCorrect(I) );
    end
end

fprintf('[%s]: %3.2f%% correct.\n', stim.scriptName, ...
            stim.responses.percentCorrect);

return


