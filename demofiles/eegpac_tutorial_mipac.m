%% Demo script for phase amplitude coupling toolbox.
%% MIPAC
%
% Generates artificial amplitude modulated data then applies methods to detect  
% phase amplitude coupling (PAC).
%
% This toolbox supports the following methods :
% 
% * Mean Vector Length Modulation Index _Canolty et al. 2006_
% * Kullback-Leibler Modulation Index _Tort et al. 2010_
% * Generalized Linear Model _Penny et al. 2008_
% * MIPAC _Martinez-Cancino et al. 2018_
% 
%
% This demo is focused on the MIPAC application. In order to illustrate its
% usage, multiple trial and single trial PAC data are simulated. PAC
% estimation is performed using Instantaneous MIPAC and ER-MIPAC
% Codes to perform the estimation are provided.
%
% Notes :
% In order to make the simulation more realistic noise was added and the
% data was shifted a randon dumber of samples (from 1:100) in time.
%
% Authors: Ramon Martinez Cancino,SCCN/INC, UCSD 2016
%
% Copyright (C) 2018 Ramon Martinez Cancino,UCSD, INC, SCCN

%% Single trial simulated PAC signal generation
% Parameters to generate single trial data
% Signal parameters
fcarrier      = 40;   % Frequency of the carrier wave
fmodulating   = 5;    % Frequency of the modulating wave.

max_time      = 5;    % Time of the simulation. In seconds.
s_rate        = 256;  % Sampling rate in Hz.
padtime       = 1;    % Padding time at the start and end of the signal. 
snrval        = Inf;    % Signal to noise ratio.
nsegm         = 5;    % Number of segments in the data. Each segment is a block with or without modulation

% Generate single trial PAC data
tlimitsgensignal     = [0.001 max_time];
%% CHANGE FUNCTION BELOW BY THE RIGHT ONE
[data_pac, time]    = generate_pac_signal(fcarrier,fmodulating,tlimitsgensignal,'Ac',5,'Am',1,'fs',s_rate,'cpfunc'     ,'block'...  
                                                                                         ,'blockamp'  ,1 ...
                                                                                         ,'nsegm'     ,nsegm...
                                                                                         ,'plot_flag' ,1 ...
                                                                                         ,'padtime'   ,padtime...
                                                                                         ,'snr'       ,snrval...
                                                                                         ,'m'         ,1 ...
                                                                                         ,'method'    ,'wiki');
%% Compute PAC using Instanteaneous MIPAC method

% Method parameters           
method      = 'instmipac';  % Instantaneous MIAPC (Martinez-Cancino et al. 2018)
% nfreqsphase = 1;            % Number of frequencies used for the phase.
% nfreqsamp   = 1;            % Number of frequencies used for the amplitude.
% phaserange  = fmodulating;  % Range of phases to be used
% amprange    = fcarrier;     % Range of amplitudes to be used
tlimits     = minmax(time); % Time limits

phaserange  = [3 4];  % Range of phases to be used
amprange    = [50 60];  % Range of amplitudes to be used
nfreqsphase = 2;            % Number of frequencies used for the phase.
nfreqsamp   = 2;            % Number of frequencies used for the amplitude.

[instmipacval, ~, ~, ~, ~, ~,~,~, instmipacstruct] = eeg_pac(data_pac', data_pac', s_rate,'freqs'     ,phaserange ...
                                                                                         ,'freqs2'    ,amprange...
                                                                                         ,'alpha'     ,[]...
                                                                                         ,'methodpac' ,method...
                                                                                         ,'nfreqs1'   ,nfreqsphase ...
                                                                                         ,'nfreqs2'   ,nfreqsamp ...
                                                                                         ,'tlimits'   , tlimits ...
                                                                                         ,'winsize'   ,s_rate);    
                                                                                     
%% Generate multiple trial data

%% Generating data
ntrials  = 100; % Number of trials
maxshift = 100; 

datamat = repmat(data_pac,ntrials,1);
s = randi(maxshift, ntrials,1);

for i=1:ntrials
     datamatwn(i,:) = awgn(datamat(i,:),50,'measured');    
     datatmp(i,:) = [datamatwn(i,s(i):end) datamatwn(i,1:s(i)-1)];
     datamatwn(i,:) = [datatmp(i,end-ceil(maxshift/2):end) datatmp(i,1:end-ceil(maxshift/2)-1)]; 
end

%% Compute PAC using Event Related MIPAC method

% Method parameters           
method      = 'ermipac';  % Instantaneous MIAPC (Martinez-Cancino et al. 2018)
% nfreqsphase = 1;            % Number of frequencies used for the phase.
% nfreqsamp   = 1;            % Number of frequencies used for the amplitude.
% phaserange  = fmodulating;  % Range of phases to be used
% amprange    = fcarrier;     % Range of amplitudes to be used
tlimits     = minmax(time); % Time limits

phaserange  = [3 4];  % Range of phases to be used
amprange    = [50 60];  % Range of amplitudes to be used
nfreqsphase = 2;            % Number of frequencies used for the phase.
nfreqsamp   = 2;            % Number of frequencies used for the amplitude.

%%
[instmipacval, ~, ~, ~, ~, ~,~,~, instmipacstruct] = eeg_pac(datamatwn', datamatwn', s_rate,'freqs'     ,phaserange ...
                                                                                         ,'freqs2'    ,amprange...
                                                                                         ,'alpha'     ,[]...
                                                                                         ,'methodpac' ,method...
                                                                                         ,'nfreqs1'   ,nfreqsphase ...
                                                                                         ,'nfreqs2'   ,nfreqsamp ...
                                                                                         ,'tlimits'   , tlimits ...
                                                                                         ,'winsize'   ,s_rate ...
                                                                                         ,'timefreq'  , 1 );    

