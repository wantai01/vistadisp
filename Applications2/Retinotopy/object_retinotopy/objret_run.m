function stim = objret_run(scriptName, subject, varargin);
% stim = objret_run([scriptName, subject, options]);
%
% Run a object bar retinotopy stimulus, based on a script.
%
% SEE: objret_makescript, saveObjectBarImages, objectBar.
%
% ras, 07/15/2008. 
if notDefined('scriptName')
	scriptName = 'housebar_blanks_1.txt';
end

if notDefined('subject'),	subject = '';		end

tic

%% parameters
stim.circMask = 1;  % add a circular mask to the images
stim.cmap = gray(256); 
stim.nRunRepeats = 1;
stim.TR = 2;
stim.startScan = 3 * stim.TR; % when do we send the trigger to start scanning?
stim.nFixColors = 3;  % # colors for fixation task
stim.speak = 0;		% flag to speak (Most likely in a creepy voice...)
stim.bgColor = 127;
stim.responseKeys = {'5' '4' '3' '2'}; % keys for colors in fixation task
stim.runPriority = 7;
stim.scriptName = scriptName;

%% parse optional params
for ii = 1:2:length(varargin)
	eval( sprintf('stim.%s = %s', varargin{ii}, num2str(varargin{ii+1})) );
end
	
%% load the parameters for this display
stim.display = loadDisplayParams(prefsDisplayName);
stim.display.backColorIndex = stim.bgColor;
stim.display.backColorRgb = [stim.bgColor stim.bgColor stim.bgColor 255];

% update the display params to match the actual display settings
res = Screen('Resolution', stim.display.screenNumber);
stim.display.numPixels = [res.width res.height];
stim.display.frameRate = res.hz;
stim.display.bitsPerPixel = res.pixelSize;
stim.display.fixX = round(res.width/2);
stim.display.fixY = round(res.height/2);

%% read in the script
stim = objret_readscript(stim, scriptName);

%% fill in the stimulus structure with other required fields:
% fixSeq, etc.
stim = objret_stimParams(stim);

fprintf('[%s]: load time: %i min %2.1f sec.\n', mfilename, floor(toc/60), ...
		mod(toc, 60));

%% run the stimulus
stim = runStimulus(stim);

%% close up
stim = closeDisplay(stim, subject);

return
% /------------------------------------------------------------/ %



% /------------------------------------------------------------/ %
function stim = objret_readscript(stim, scriptName);
%% Read in the information in a script file to a stim struct.
if ~exist(scriptName, 'file')
	% check in the scripts dir (also ensure a .txt extension is given)
	codeDir = fileparts(which(mfilename));
	scriptDir = fullfile(codeDir, 'Scripts');
	
	[p f ext] = fileparts(scriptName);
	altName = fullfile(scriptDir, [f '.txt']);
	
	if exist(altName, 'file')
		scriptName = altName;
	else
		error( sprintf('Script %s not found.', scriptName) );
	end
end

%% init empty stim fields
stim.seqtiming = [];
stim.seq = [];
stim.fixSeq = [];
stim.images = {};
stim.position = [];
stim.direction = [];
stim.blockNum = [];

% create a tmp structure for image paths: this is for back-compatibility
% with the existing 'countImages' tool imported from KGS stim tools;
tmp.image = {};

%% open the file
fid = fopen(scriptName, 'r');

% skip the header lines: 4 lines
for n = 1:4
	fgetl(fid);
end

%% read in the main lines
while ~feof(fid)
	ln = fgetl(fid);
	
	vals = explode( sprintf('\t'), ln );
	
	if length(vals) < 5
		if findstr(ln, '***')    % end of run indicator
			break
		else
			error( sprintf('Improperly formed line. %s', ln) );
		end
	end
	
	stim.blockNum(end+1) = str2num(vals{1});
	stim.seqtiming(end+1) = str2num(vals{2});
	stim.fixSeq(end+1) = 1;  % dummy value
	stim.direction(end+1) = str2num(vals{3});
	stim.position(end+1) = str2num(vals{4});
	
	% record the image path in the temp structure
	tmp.image{end+1} = vals{5};
end

% done with the file
fclose(fid);

%% now, set up the images:
fprintf('[%s]: Loading images.', mfilename);

% set the 'seq' field by finding where each image lies
stim.seq = countImages(tmp);

% for stim.seq > 0, these are actual image files, load 'em
for n = 1:max(stim.seq)
	I = find(stim.seq==n);

	[p f ext] = fileparts( tmp.image{I(1)} ); % ignores trailing spaces
	img = imread( fullfile(p, f), 'png' );
	
	stim.images{n} = scaleContrast(img, 252/256);
	
	stim.seq(I) = n;
	stim.imgpath{n} = fullfile(p, [f ext]);
	
	fprintf('.');
	if mod(n, 100)==0
		fprintf('\n');
	end
end

% for stim.seq < 0, set up a blank image as the last image and point to
% that:
sz = size(stim.images{1});
stim.images{end+1} = repmat(uint8(stim.bgColor), [sz(1:2)]);
stim.seq(stim.seq < 0) = length(stim.images); % point to blank image

stim.imgpath{end+1} = 'blank';

% also set the first seq entry to -1: this sets the color map
stim.seq(1) = -1;

% convert images from cell -> 3D matrix
stim.images = cell2mat(stim.images);
stim.images = reshape(stim.images, [sz(1) sz(2) length(stim.imgpath)]);

fprintf('done.\n');

return
% /------------------------------------------------------------/ %



% /------------------------------------------------------------/ %
function stim = objret_stimParams(stim);
%% set up stimulus fields needed for the exptTools2 functions

% % center the images on the display
% stim.images = makeScreenSizeImages(stim.images, stim.display.numPixels, 127);

% mask the images if selected
if stim.circMask==1
	sz = size(stim.images);
	mask = makecircle(sz(1)-3, sz(1), 2);
	mask = makeScreenSizeImages(mask, sz([2 1 3]), 0);
	for n = 1:sz(3)
		tmp = stim.images(:,:,n);
		tmp = uint8( double(tmp) .* mask );
		tmp(mask==0) = stim.bgColor;
		stim.images(:,:,n) = tmp; 
	end
end

% set the fixation colors on the color map
stim.cmap(end,:) = [1 0 0];
stim.images = scaleContrast(stim.images, (255-stim.nFixColors)/256);

%% set fixation sequence: color detection task
% set the colors to use for the fixation
defColors = [1 1 1; 0 0 1; 0 .8 0; 1 0 0; 1 1 0];
stim.cmap(end-stim.nFixColors:end,:) = defColors(1:stim.nFixColors+1,:);

% rescale the rest of the cmap to span the whole grayscale range
stim.cmap(1:255-stim.nFixColors,:) = gray(255-stim.nFixColors);

% (NOTE: the main function, called when running the stimulus, is
% drawFixation: this function sets the fixation in such a way that
% display.fixColorRgb serves as an index into the cmap, even though it may
% seem like a list of [R G B] truecolor triplets.)
stim.display.fixColorRgb = [];
for n = 1:stim.nFixColors+1
	stim.display.fixColorRgb(n,:) = repmat(254 - stim.nFixColors + n, [1 3]);
end

% (re-) initialize the fixation sequence with ones: 
% this will point to the default, non-prompt color
stim.fixSeq = ones(size(stim.seq));

% prompt every 2 seconds
promptTime = 2:2:max(stim.seqtiming);
promptTime = promptTime(1:end-1); % last prompt comes around end of run 

% % ALTERNATE:
% % choose randomized timing of fixation color changes
% minISI = 2; % give at least 2 sec b/w prompts
% maxISI = 6; % prompt at least once every 6 sec
% promptTime = [2]; % 1st prompt at exactly 2 sec into run
% while max(promptTime) < max(stim.seqtiming)   % while there's till time in the run
% 	promptTime(end+1) = promptTime(end) + minISI + (maxISI-minISI) * rand;
% end
% promptTime = promptTime(1:end-1); % lob off last prompt: comes after run ends

% round these prompt times to the nearest onset specified in seqtiming
for n = 1:length(promptTime)
	I = find( stim.seqtiming < promptTime(n) );
	promptTime(n) = stim.seqtiming(I(end));
	promptFrame(n) = I(end);
end

% for each prompt frame (and the 2 following: give it a duration),
% randomly assign one of nFixColors as the fixation color
for ii = unique(promptFrame)
	% +1 offset: first entry is the baseline fixation color
	stim.fixSeq(ii:ii+2) = ceil( stim.nFixColors * rand ) + 1;
end

% keep track of when the prompts occur
stim.promptTime = promptTime;
stim.promptFrame = promptFrame;

% set the prompt for the fixation task (TODO: parametrize this)
stim.taskStr = 'Fixation color: (1) blue (2) green (3) red';

return
% /----------------------------------------------------------------/ %




% /----------------------------------------------------------------/ %
function images = makeScreenSizeImages(srcImages, screenSize, bg);
%% given a set of images which may be larger than a given screen size, 
%% return a set of images the same size as the screen, with the images
%% centered within it. The rest of the image will be padded with the
%% background value bg (takes corner pixel of 1st image as default). 
if notDefined('bg'), bg = srcImages(1); end

screenX = screenSize(1);
screenY = screenSize(2);

sz = size(srcImages);  sz(3) = size(srcImages, 3);  % force 3rd dim
if sz(1) > screenY | sz(2) > screenX
	warning('images are already larger than the screen!');
	return
end

images = repmat(bg, [screenY screenX sz(3)]);
rows = ceil( [1:sz(1)] + screenY/2 - sz(1)/2 );
cols = ceil( [1:sz(2)] + screenX/2 - sz(1)/2 );
for n = 1:sz(3)
	images(rows,cols,n) = uint8(srcImages(:,:,n));
end

return
% /---------------------------------------------------------------------/ %




% /---------------------------------------------------------------------/ %
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
    
    % Store the images in textures
    stim = createTextures(stim.display, stim, 1);

    % getting to the source rather than doScan->doTrial->showStimulus 
    for n = 1:stim.nRunRepeats,
        % set priority
        Priority(stim.runPriority);
        
        % wait for go signal
        pressKey2Begin(stim.display, [], [], stim.taskStr);      

        % countdown + get start time (time0)
        [time0] = countDown(stim.display, stim.startScan+2, stim.startScan);
        time0   = time0 + stim.startScan; % we know we should be behind by that amount

		% put up a blank screen
		Screen('DrawTexture', stim.display.windowPtr, stim.textures(end), stim.srcRect, stim.destRect);
        drawFixation(stim.display, stim.fixSeq(1));
		Screen('Flip', stim.display.windowPtr);
		
        % go
        [response, timing, quitProg] = showColorStimulus(stim.display, stim, time0);
        
		% record responses
		stim.responses(n) = response;
		
        % reset priority
        Priority(0);
		
		% report timing
        fprintf('Done. Total stimulus duration: %i min %2.1f sec. \n', ...
				floor((getSecs-time0)/60), mod((getSecs-time0), 60)); 

		% keep going?
        if quitProg, % don't keep going if quit signal is given
            break;
        end;
    end;
    
    % Close the one on-screen and many off-screen windows
    closeScreen(stim.display);
	
	% compute performance on the task
	stim = computeTaskPerformance(stim);
	
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
function stim = computeTaskPerformance(stim);
%% calculate the user's performance on the fixation color-detection task,
%% reporting it in the command line, saying it (if stim.speak==1), and
%% storing it in stim.responses.RT and stim.responses.percentCorrect.
% First, initialize a set of correct/incorrect flags and RTs for each
% prompt:
stim.responses.correct = repmat(NaN, [1 length(stim.promptFrame)]);
stim.responses.RT = repmat(NaN, [1 length(stim.promptFrame)]);

% Next, let's find the times when keypresses
% were made, and see if they correspond to the correct color:
keypressFrames = find(stim.responses.keyCode);
for f = keypressFrames(:)'
	lastPrompt = max( stim.promptFrame(stim.promptFrame < f) );
	promptIndex = find( stim.promptFrame==lastPrompt );
	
	correctResp = stim.fixSeq(lastPrompt) - 1; %-1 b/c of non-prompt fix color
	
	
	% find out whether the key which was pressed maps to one of the
	% designated response keys; and if so, which one:
	k = KbName(stim.responses.keyCode(f));
	responseIndex = strmatch( lower(k(1)), lower(stim.responseKeys) );
	
	if isempty(responseIndex)
		% invalid key pressed: incorrect by default
		stim.responses.correct(promptIndex) = 0;
	else
		% may be correct: was it the right key?
		stim.responses.correct(promptIndex) = (responseIndex==correctResp);
	end
	
	% get the response time (in msec)
	rt = stim.responses.secs(f) - stim.promptTime(promptIndex);
	stim.responses.RT(promptIndex) = 1000 * rt;
end

% the remaining prompts, for which no keypress is recorded, are incorrect
% by default:
% we'll leave the RTs at NaN to indicate no keypress as well
stim.responses.correct( isnan(stim.responses.correct) ) = 0;

% compute the overall percent correct
stim.responses.percentCorrect = 100 * ...
	sum(stim.responses.correct) / length(stim.responses.correct);

%% report the results
msg = sprintf('%i Percent Correct', round(stim.responses.percentCorrect));
fprintf('[%s %s]: %s\n', mfilename, stim.scriptName, msg);
if stim.speak==1
    eval('system(sprintf(''say %s'',msg));',''); 
end

return
% /---------------------------------------------------------------------/ %




% /---------------------------------------------------------------------/ %
function stim = closeDisplay(stim, subj);
%% close the PsychToolbox display and finish up
closeScreen(stim.display);
Screen('CloseAll');
setGamma(0);
Priority(0);
ShowCursor;

if ~isempty(subj)
	%% save the performance data
	condition = [mfilename '_' getToday];

	colorDir = fileparts( which(mfilename) );  % same directory as this code
	dataDir = fullfile(colorDir, 'Data');
	ensureDirExists(dataDir);
	
	fullFileName = fullfile(dataDir, [subj '_' condition '.mat']);
	if exist(fullFileName,'file')
		load(fullFileName);
		fullRecord(end+1) = stim;
	else
		fullRecord = stim;
	end
	
	save(fullFileName, 'fullRecord');
	fprintf('Saved scan parameters / subject performance in %s.\n', fullFileName);
end

return

