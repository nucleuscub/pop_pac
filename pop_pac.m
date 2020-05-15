% pop_pac() - Call GUI to compute cross-frequency-coupling coupling.
%             Second level function to compute CFC by calling eeg_pac.m
% Usage:
%   >>  pac = pop_pac(EEG);
%
% Inputs:
%  EEG          - [Structure] Input dataset as an EEGLAB EEG structure
%  pooldata     - ('channels' || 'component' ). Define if compute CFC in
%                 channel or ICA decomposed data
%  freqs1       - [min max] Range of frequency to consider for the phase values.
%  freqs2       - [min max] Range of frequency to consider for the amplitude values.
%  indexfreqs1  - [Integer]Index of the channel or component to use to in freqs1
%  indexfreqs2  - [Integer]Index of the channel or component to use to in freqs2
%
% Optional inputs:
% Note: Optional parameters of eeg_pac can be provided as input as well
%  method       - {'mvlmi','klmi','glm','instmipac', 'ermipac'}.CFC method .
%                 Default: 'glm'. (currently PAC methods only)
%  nboot        - [Integer] Number of surrogates generated for statistical significance analysis. Default: [200] 
%  alpha        - [Real] Significance threshold. Default: [0.05]
%  bonfcorr     - [1,0] Flag to perform multiple comparisons correction.Default: [0] 
%                 using Bonferroni. Default: [0](do not perform correction)
%  nfreqs1      - [Integer]Number of frequencies in the 'freqs1' range. Default: [1] 
%  nfreqs2      - [Integer]Number of frequencies in the 'freqs2' range. Default: [1] 
%  cleanup      - [1,0] Flag to remove previous results in the EEG
%                 structure. Default: [0] (Do not clean up structure)
%  ptspercent   - [0.01:0.5] Size in percentage of data of the segments to shuffle 
%                 when creating surrogate data. Default: [0.05] 
%  forcecomp    - [0,1] Flag to force (1) or not (0) the computation of PAC
%                 in the case it is detected that the measure has been
%                 computed already. Default:[0]
% Outputs:
%  EEG          - EEGLAB EEG structure. Results of computing CFC are
%                  stored in EEG.etc.pac
%  com          - Command for EEG history
% See also:
%
% Author: Ramon Martinez-Cancino, SCCN, 2019
%
% Copyright (C) 2019  Ramon Martinez-Cancino,INC, SCCN
%
% This program is free software; you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation; either version 2 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with this program; if not, write to the Free Software
% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

function [EEG,com] = pop_pac(EEG,pooldata,freqs1,freqs2,indexfreqs1,indexfreqs2,varargin)
com = '';

if nargin == 0
    help pop_pac;
    return;
end
if isempty(EEG) || isempty(EEG.data)
    fprintf(2,'pop_pac error : Unsuported input has been provided \n');
    return;
end
EEG = eeg_checkset(EEG);

% get inputs here
[tmp,tmp,dim_trial] = size(EEG.data); clear tmp;

try
    options = varargin;
    if ~isempty( varargin )
        for i = 1:2:numel(options)
            g.(options{i}) = options{i+1};
        end
    else
        g = [];
    end
catch
    disp('pop_pac() error: calling convention {''key'', value, ... } error'); return;
end
try g.freq1_trialindx;      catch, g.freq1_trialindx  =  1:dim_trial; end % Opt only for pop_pac
try g.freq2_trialindx;      catch, g.freq2_trialindx  =  1:dim_trial; end % Opt only for pop_pac

try g.nboot;                catch, g.nboot            =  200;         end
try g.alpha;                catch, g.alpha            =  0.05;        end
try g.bonfcorr;             catch, g.bonfcorr         =  0;           end
try g.method;               catch, g.method           =  'glm';       end
try g.nfreqs1;              catch, g.nfreqs1          =  1;           end
try g.nfreqs2;              catch, g.nfreqs2          =  1;           end
try g.cleanup;              catch, g.cleanup          =  0;           end
try g.freqscale;            catch, g.freqscale        =  'log';       end % may be 'linear' or 'log'
try g.ptspercent;           catch, g.ptspercent       =  0.05;        end 
try g.forcecomp;            catch, g.forcecomp        =  0;           end
try g.compflag;             catch, g.compflag         = 'local';      end
try g.runtime;              catch, g.runtime          = 1;            end
try g.jobid;                catch, g.jobid            = ['pacssnsg_' num2str(floor(rand(1)*1000000))]; end

if nargin < 6 
    
    % Closing open GUI and creating a new one
    openfig = findobj('tag', 'pop_pacgui');
    if ~isempty(openfig)
        disp('pop_pac warning: there can be only one pop_pac window, closing old one...')
        close(openfig); 
    end
    
    % Checking NSG
    nsginstalled_flag = 1;
    try
        nsg_info;  % From here, get information on where to create the temporary file
    catch
        nsginstalled_flag = 0;
    end
    
    % Defaults for GUI
    freqs1         = [4 15];
    freqs2         = [EEG.srate/4-20 EEG.srate/4-2];
    nfreqs1        = length(freqs1(1):2:freqs1(2));
    nfreqs2        = length(freqs2(1):3:freqs2(2)) ;
    freq1_dataindx = 1;
    freq2_dataindx = 1;
    
    % ---
    % Checking if ICA
    if isempty(EEG.icawinv)
        datatypel_list = {'Channels'} ;
    else
        datatypel_list = {'Channels','Components'} ;
    end
    
    % Here define other types of CFC
    % Note: In case of adding more methods, add the modality here at the
    % end of the cell array, and then update 'data1_list' and 'data2_list'
    % in the callback 'callback_setdata'
    
    cb_popmenu_datatype = 'set(findobj(''tag'', ''freq1_dataindx''), ''string'', '' ''); set(findobj(''tag'', ''freq2_dataindx''), ''string'', '' '');';
    nsgcheck = ['if ' num2str(nsginstalled_flag) ',if get(findobj(''tag'',''chckbx_nsgt''),''value''),' ...
                        'set(findobj(''tag'',''nsgopt''),''enable'', ''on'');'...
                     'else, set(findobj(''tag'',''nsgopt''),''enable'', ''off'');end;'...
                   'else, set(findobj(''tag'',''nsgopt''),''enable'', ''off''); set(findobj(''tag'',''chckbx_nsgt''),''value'',0); end'];
    
%    cfctype_list = {'Phase-Amp'};%, 'Amp.-Amp.', 'Phase-Phase'}; 
    
   cbdataindx1 =   [ 'set(findobj(''tag'', ''freq1_dataindx''), ''string'', '' '');'...
                    'if get(findobj(''tag'',''datatype''),''value'') == 1,' ...
                    '   if isempty(EEG(1).chanlocs),'...
                    '     chanlist = cellfun(@(x) [''Chan'' num2str(x)],num2cell(1:size(EEG.data,1)), ''UniformOutput'',0);'...
                    '     [datindx1,datstr] = pop_chansel(chanlist);'...
                    '   else;'...
                    '        [datindx1,datstr] = pop_chansel({EEG(1).chanlocs.labels});' ...
                    '   end;'...
                    '   else,' ...
                    '         iclist = cellfun(@(x) [''IC'' num2str(x)],num2cell(1:size(EEG.icawinv,2)), ''UniformOutput'',0);'...
                    '         [datindx1,datstr] =  pop_chansel(iclist);' ...
                    'end;' ...
                    'if ~isempty(datstr)' ...
                    '      set(findobj(''tag'', ''freq1_dataindx''), ''string'', datstr);' ...
                    'end;'...
                    'myappdata = getappdata(findobj(''tag'', ''pop_pacgui''),''userdata'');'...
                    'myappdata.freqindx1 = datindx1;'...
                    'setappdata(findobj(''tag'', ''pop_pacgui''), ''userdata'', myappdata);'...
                    'set(findobj(''tag'', ''pop_pacgui''), ''userdata'', myappdata);' ];
                
   cbdataindx2 =   [ 'set(findobj(''tag'', ''freq2_dataindx''), ''string'', '' '');'...
                    'if get(findobj(''tag'',''datatype''),''value'') == 1,' ...
                    '   if isempty(EEG(1).chanlocs),'...
                    '     chanlist = cellfun(@(x) [''Chan'' num2str(x)],num2cell(1:size(EEG.data,1)), ''UniformOutput'',0);'...
                    '     [datindx2,datstr] = pop_chansel(chanlist);'...
                    '   else;'...
                    '        [datindx2,datstr] = pop_chansel({EEG(1).chanlocs.labels});' ...
                    'end;'...
                    '   else,' ...
                    '         iclist = cellfun(@(x) [''IC'' num2str(x)],num2cell(1:size(EEG.icawinv,2)), ''UniformOutput'',0);'...
                    '         [datindx2,datstr] =  pop_chansel(iclist);' ...
                    'end;' ...
                    'if ~isempty(datstr)' ...
                    '      set(findobj(''tag'', ''freq2_dataindx''), ''string'', datstr);' ...
                    'end;'...
                    'myappdata = getappdata(findobj(''tag'', ''pop_pacgui''),''userdata'');'...
                    'myappdata.freqindx2 = datindx2;'...
                    'setappdata(findobj(''tag'', ''pop_pacgui''), ''userdata'', myappdata);'...
                    'set(findobj(''tag'', ''pop_pacgui''), ''userdata'', myappdata);' ];
                
   
    method_listgui = {'Mean vector length modulation index (Canolty et al.)',...
                      'Kullback-Leibler modulation index (Tort et al.)',...
                      'General linear model (Penny et al.)',...
                      'Phase Locking Value (Lachaux et al.)',...
                      'Instantaneous MIPAC (Martinez-Cancino et al.)',...
                      'Event related MIPAC (Martinez-Cancino et al.)'};
    method_list    = {'mvlmi','klmi','glm','plv','instmipac', 'ermipac'};
    guititle = 'Estimate event-related cross-frequency coupling -- pop_pac()'; 
    callback_chkcbxstat = ['label_statsate = {''(on)'', ''(off)''};'... 
                           'set(findobj(''tag'', ''label_statstate''), ''string'', label_statsate{fastif(get(findobj(gcf,''tag'', ''chckbx_stat''), ''value''),1,2)});'...
                           'if get(findobj(''tag'',''chckbx_stat''),''value''),' ...
                           'set(findobj(''tag'',''nsurrogates''),''enable'', ''on'');'...
                           'set(findobj(''tag'',''nblocks_edit''),''enable'', ''on'');'...
                           'set(findobj(''tag'',''pvalue''),''enable'', ''on'');'...
                           'set(findobj(''tag'',''bonfcorr''),''enable'', ''on'');'...
                           'else, set(findobj(''tag'',''nsurrogates''),''enable'', ''off'');'...
                           'set(findobj(''tag'',''nblocks_edit''),''enable'', ''off'');'...
                           'set(findobj(''tag'',''pvalue''),''enable'', ''off'');'...
                           'set(findobj(''tag'',''bonfcorr''),''enable'', ''off'');end;'];
                     
    callback_chkcbx_logphs = 'set(findobj(''tag'',''chckbx_logamp''), ''value'', get(findobj(''tag'',''chckbx_logphs''),''value''))';
    callback_chkcbx_logamp = 'set(findobj(''tag'',''chckbx_logphs''), ''value'', get(findobj(''tag'',''chckbx_logamp''),''value''))';
    
    if nsginstalled_flag
    guiheight = 12;
    guiwidth = 2.6;
    nsgdefaultopt = ['''runtime'',' num2str(g.runtime) ',''jobid'','''  g.jobid ''''];
    nsgmenugeom = {{guiwidth guiheight [0 10]    [1 1]}  {guiwidth guiheight [0.5 10] [0.5  1]}...
                   {guiwidth guiheight [0 11]    [1 1]}  {guiwidth guiheight [0.5 11] [2.1  1]}...
                   {guiwidth guiheight [0 12]    [1 1]}};
    nsgmenuuilist = {{'style' 'text' 'string' 'Compute on NSG' 'fontweight' 'bold'} {'style' 'checkbox' 'tag' 'chckbx_nsgt' 'callback' nsgcheck 'value' fastif(strcmpi(g.compflag,'nsg'), 1, 0)}...
                    {'style' 'text' 'string' 'NSG options'}    {'style' 'edit'       'string'  nsgdefaultopt           'tag' 'nsgopt' 'enable' fastif( strcmpi(g.compflag,'nsg'), 'on','off')}...
                    {}};
    else
        guiheight = 9
        nsgmenugeom =  {{guiwidth guiheight [0 10]    [1 1]}};
        nsgmenuuilist = {{}};
    end
    
    userdata = [];
    geometry = { {guiwidth guiheight [0 0]     [1 1]}  {guiwidth guiheight [0.3  0] [0.8 1] }...%  {guiwidth 9 [1.58 0]  [1 1]}    {guiwidth 9 [1.9 0] [0.83 1] }...
                                                  {guiwidth guiheight [0.6  1] [0.58 1]}                                    {guiwidth guiheight [1.37 1] [0.55 1]} {guiwidth guiheight [1.9 1] [0.38 1]} {guiwidth guiheight [2.25 1] [0.4 1]}...
                 {guiwidth guiheight [0.18 2]  [1 1]}  {guiwidth guiheight [0.6  2] [0.6 1]} {guiwidth guiheight [1.12  2] [0.24 1]}  {guiwidth guiheight [1.37 2] [0.55 1]} {guiwidth guiheight [1.9 2] [0.38 1]} {guiwidth guiheight [2.32 2] [0.3 1]}...
                 {guiwidth guiheight [0.18 3]  [1 1]}  {guiwidth guiheight [0.6  3] [0.6 1]} {guiwidth guiheight [1.12  3] [0.24 1]}  {guiwidth guiheight [1.37 3] [0.55 1]} {guiwidth guiheight [1.9 3] [0.38 1]} {guiwidth guiheight [2.32 3] [0.3 1]}...
                 {guiwidth guiheight [0 4]     [1 1]}  {guiwidth guiheight [0.58  4] [2.03 1]}...
                 {guiwidth guiheight [0 5]     [1 1]}  {guiwidth guiheight [0.6  5]  [2  1]}...
                 {guiwidth guiheight [0 6]     [1 1]}  {guiwidth guiheight [0.6  6] [2.1  1]}...
                 {guiwidth guiheight [0.15 7]  [1 1]}  {guiwidth guiheight [1 7] [0.5  1]}  {guiwidth guiheight [1.75  7] [1 1]} {guiwidth guiheight [2.1  7] [0.5 1]}...
                 {guiwidth guiheight [0.15 8]  [1 1]}  {guiwidth guiheight [1 8] [0.5  1]}...
                 {guiwidth guiheight [0.15 9]  [1 1]}  {guiwidth guiheight [1 9] [0.5  1]}...
                 nsgmenugeom{:}};
             
    uilist = {{'style' 'text' 'string' 'Data type' 'fontweight' 'bold' } {'style' 'popupmenu' 'string' datatypel_list 'tag' 'datatype' 'value' 1 'callback' cb_popmenu_datatype}...% {'style' 'text' 'string' 'CFC type' 'fontweight' 'bold' } {'style' 'popupmenu' 'string' cfctype_list 'tag' 'datatyppac' 'value' 1 'callback' callback_setdata}...% 
              {'style' 'text' 'string' 'Select Comp/chan' 'fontweight' 'normal'} {'style' 'text' 'string' 'Freq range [lo hi] (Hz)' 'fontweight' 'normal'} {'style' 'text' 'string' '# Frequencies' 'fontweight' 'normal'} {'style' 'text' 'string' 'Log-scaling' 'fontweight' 'normal'} ...
              {'style' 'text' 'string' 'Phase data' 'fontweight' 'normal' 'tag' 'data1'} {'style' 'edit' 'string' ' ' 'tag' 'freq1_dataindx'} { 'style' 'pushbutton' 'string' '...' 'callback' cbdataindx1 } ...
                                                                                                {'style' 'edit' 'string' num2str(freqs1)         'tag' 'freq1'}...
                                                                                                {'style' 'edit' 'string' num2str(nfreqs1)        'tag' 'nfreqs1'}...
                                                                                                {'style' 'checkbox' 'tag' 'chckbx_logphs' 'callback' callback_chkcbx_logphs 'value' 1}...
              {'style' 'text' 'string' 'Amp data ' 'fontweight' 'normal' 'tag' 'data2'} ...
                                                                                                {'style' 'edit' 'string' ' ' 'tag' 'freq2_dataindx'} { 'style' 'pushbutton' 'string' '...' 'callback' cbdataindx2 } ......
                                                                                                {'style' 'edit' 'string' num2str(freqs2)        'tag' 'freq2'}...
                                                                                                {'style' 'edit' 'string' num2str(nfreqs2)        'tag' 'nfreqs2'}...
                                                                                                {'style' 'checkbox' 'tag' 'chckbx_logamp' 'callback' callback_chkcbx_logamp 'value' 1}...
              {'style' 'text' 'string' 'PAC method' 'fontweight' 'bold'} {'style' 'popupmenu' 'string' method_listgui 'tag' 'method'}...
               {'style' 'text' 'string' 'Optional inputs' 'fontweight' 'bold'} {'style' 'edit' 'string' ' ' 'tag' 'edit_optinput'}...
              {'style' 'text' 'string' 'Significance testing' 'fontweight' 'bold'} {'style' 'checkbox' 'tag' 'chckbx_stat' 'callback' callback_chkcbxstat 'value' 0}...
              {'style' 'text' 'string' '# Surrogates' 'callback' 'close(gcbf);' } {'style' 'edit' 'string' num2str(g.nboot) 'tag' 'nsurrogates' 'enable' 'off'}  {'style' 'text' 'string' '# data blocks' 'callback' 'close(gcbf);' } {'style' 'edit' 'string' num2str(1/g.ptspercent) 'tag' 'nblocks_edit' 'enable' 'off'} ...
              {'style' 'text' 'string' 'Significance threshold (0<p<1)' 'callback' 'close(gcbf);' } {'style' 'edit' 'string' num2str(g.alpha) 'tag' 'pvalue' 'enable' 'off'}... 
              {'style' 'text' 'string' 'Correct for multiple comparisons' 'callback' 'close(gcbf);' } {'style' 'checkbox' 'tag' 'bonfcorr' 'enable' 'off'}...
              nsgmenuuilist{:}};
          
    [out_param userdat tmp res] = inputgui('title', guititle, 'geom', geometry, 'uilist',uilist,'eval', 'set(gcf,''tag'', ''pop_pacgui''); setappdata(findobj(''tag'', ''pop_pacgui''),''userdata'',struct(''freqindx1'', [], ''freqindx2'', []))', 'helpcom','pophelp(''pop_pac'');');
%%
    % Retreiving Inputs
    if isempty(res), return; end 
    
    indexfreqs1 = userdat.freqindx1;
    indexfreqs2 = userdat.freqindx2;
    pooldata    = datatypel_list{res.datatype};
    freqs1      = str2num(res.freq1);
    freqs2      = str2num(res.freq2);
    freqscale   = fastif(res.chckbx_logamp, 'log', 'linear');
    
    % Applying Bonferroni correction for the number of channel/components
    % computed
    if res.chckbx_stat
        if res.bonfcorr && ~isempty(res.pvalue)
            res.pvalue = str2num(res.pvalue) / (numel(indexfreqs1) * numel(indexfreqs2));
        else
            res.pvalue = str2num(res.pvalue);
        end
    else
        res.bonfcorr = 0;
        res.pvalue   = [];
    end
    
    % Updating g. options
    g.nboot     = str2num(res.nsurrogates);
    g.alpha     = res.pvalue;
    g.bonfcorr  = res.bonfcorr;
    g.method    = method_list{res.method};
    g.nfreqs1   = str2num(res.nfreqs1);
    g.nfreqs2   = str2num(res.nfreqs2)  ;
    g.freqscale = freqscale;
    if nsginstalled_flag
        g.compflag = fastif(res.chckbx_nsgt, 'nsg', 'local');
        tmpnsg = eval( [ '{' res.nsgopt '}' ] );
        if ~isempty( tmpnsg )
            for i = 1:2:numel(tmpnsg)
                if any(strcmp(tmpnsg{i},fieldnames(g)))
                    g.(tmpnsg{i}) = tmpnsg{i+1};
                end
            end
        end
    end
    
    % Options to call eeg_pac
    options    = {'freqs'     str2num(res.freq1)       'freqs2'     str2num(res.freq2)   'nfreqs1'   g.nfreqs1 ...
                  'nfreqs2'   g.nfreqs2                'freqscale'  g.freqscale          'method'     g.method...
                  'nboot'     g.nboot                  'alpha'      g.alpha              'bonfcorr'  g.bonfcorr'...
                  'tlimits'  minmax(EEG.times)/1000};
    
    % Adding pop_pac options
    tmpparams = eval( [ '{' res.edit_optinput '}' ] );
    
    % Updating current function parameters and inputs to eeg_pac
    opttmp = tmpparams;
    if ~isempty( tmpparams )
        for i = 1:2:numel(opttmp)
            if any(strcmp(opttmp{i},fieldnames(g)))
            g.(opttmp{i}) = opttmp{i+1};
            else
                options{end+1} = opttmp{i};
                options{end+1} = opttmp{i+1};
            end
        end
    end    
else
    options = {'freqs' freqs1 'freqs2' freqs2  'tlimits'  minmax(EEG.times)/1000};
    options = {options{:} varargin{:}};
end


if strcmpi(g.compflag, 'local')
% Retreiving data
if strcmpi(pooldata,'channels')
    [dim_chan,~,dim_trial] = size(EEG.data); clear tmp;
    
    % Checking channel indices
    if ~all([all(ismember(indexfreqs1, 1:dim_chan)), all(ismember(indexfreqs2, 1:dim_chan))])
        error('Invalid data index');
    end
    
else % Component
    if isempty(EEG.icaact)
        EEG.icaact = eeg_getdatact( EEG,'component',1:size(EEG.icawinv,2));
    end
    [dim_comp,~,dim_trial] = size(EEG.data); clear tmp;
    
    % Checking component indices
    if ~all(all(ismember(indexfreqs1, 1:dim_comp)), all(ismember(indexfreqs2, 1:dim_comp)))
        error('Invalid data index');
    end
end

% Getting indices of the trials
if isempty(g.freq1_trialindx) || isempty(g.freq2_trialindx)
    g.freq1_trialindx = 1:dim_trial;
    g.freq2_trialindx = 1:dim_trial;
end

% Check if this was already computed or clean up is needed.
%--
timefreq_phase = cell(1,length(indexfreqs1));
timefreq_amp   = cell(1,length(indexfreqs2));
LastCell = 0;

compute_flag = ones(length(indexfreqs1),length(indexfreqs2));

if ~isfield(EEG.etc,'eegpac') || g.cleanup
    EEG.etc.eegpac = [];
elseif isfield(EEG.etc.eegpac,'params')
    
    if strcmpi(g.freqscale, 'log') 
        if length(freqs1) ~= 1
            inputparams.freqs_phase = linspace(log(freqs1(1)), log(freqs1(end)), g.nfreqs1);
            inputparams.freqs_phase = exp(inputparams.freqs_phase);
        else
            inputparams.freqs_phase = freqs1;
        end
        
        if length(freqs2) ~= 1
            inputparams.freqs_amp = linspace(log(freqs2(1)), log(freqs2(end)), g.nfreqs2);
            inputparams.freqs_amp = exp(inputparams.freqs_amp);
        else
            inputparams.freqs_amp = freqs2;
        end
    else
        if length(freqs1) ~= 1
            inputparams.freqs_phase = linspace(freqs1(1), freqs1(2), g.nfreqs1); % this should be OK for FFT
        else
            inputparams.freqs_phase = freqs1;
        end
        
        if length(freqs2) ~= 1
            inputparams.freqs_amp   = linspace(freqs2(1), freqs2(2), g.nfreqs2);
        else
            inputparams.freqs_amp = freqs2;
        end
    end
     inputparams.signif.alpha      = g.alpha;
     inputparams.signif.nboot      = g.nboot;
     inputparams.signif.bonfcorr   = g.bonfcorr;
     inputparams.srate             = EEG.srate;
     inputparams.pooldata          = find(strcmp({'Channels','Components'},pooldata));
     
     tmpstrc = EEG.etc.eegpac(1).params;
     tmpstrc.pooldata = EEG.etc.eegpac(1).datatype;
     tmpstrc.signif = rmfield(tmpstrc.signif,'ptspercent');
     if ~isequal(tmpstrc, inputparams)
         disp('pop_pac: Parameterers provided do not match the ones saved from previous computation.');
         disp('         Removing stored PAC results!!!!!');
         EEG.etc.eegpac = [];
     end
    
    if ~isempty(EEG.etc.eegpac)
        LastCell = length(EEG.etc.eegpac);
        % Checking Method field
        tmpfield = fieldnames(EEG.etc.eegpac(1));
        methodexist = find(strcmp(tmpfield(4:end), g.method));
        if ~isempty(methodexist)
            for ix =1:length(indexfreqs1)
                for iy = 1:1:length(indexfreqs2)
                    ChanIndxExist = find(cell2mat(cellfun(@(x) all(x==[indexfreqs1(ix) indexfreqs2(iy)]), {EEG.etc.eegpac.dataindx}, 'UniformOutput', 0)));
                    if ~isempty(ChanIndxExist) && ~isempty(EEG.etc.eegpac(ChanIndxExist).(g.method))
                        if g.forcecomp
                            disp(['pop_pac: Recomputing PAC using : ' g.method])
                            compute_flag(ix,iy) = 1;
                        else
                            disp(['pop_pac: PAC has been already computed using method: ''' g.method '''']);
                            disp(['         Aborting computation for data indices [' num2str([indexfreqs1(ix) indexfreqs2(iy)]) ']'] );
                            compute_flag(ix,iy) = 0;
                        end
                        
                    end
                end
            end
        end
    end
end
%--------------------------------------------------------------------------
c = LastCell+1;
for ichan_phase = 1:length(indexfreqs1)
    % Retreiving data for phase (X)
    if strcmpi(pooldata,'channels')
        X = squeeze(EEG.data(indexfreqs1(ichan_phase),:,g.freq1_trialindx));
    else % Component
        X = squeeze(EEG.icaact(indexfreqs1(ichan_phase),:,g.freq1_trialindx));
    end
    X = reshape(X,EEG.pnts,EEG.trials);
    %----    
    for ichan_amp = 1:length(indexfreqs2)
        if compute_flag(ichan_phase, ichan_amp)
            % Retreiving data for amplitude (Y)
            if strcmpi(pooldata,'channels')
                Y = squeeze(EEG.data(indexfreqs2(ichan_amp),:,g.freq2_trialindx));
                datatype = 1;
            else % Component
                Y = squeeze(EEG.icaact(indexfreqs2(ichan_amp),:,g.freq2_trialindx));
                datatype = 2;
            end
            Y = reshape(Y,EEG.pnts,EEG.trials);
            %----
            % Running eeg_pac
            % Three options, so we can save the TF decompositions us them
            % later in the loop. Redundant conditionals statements below
            % are to ensure a single call line  for eeg_pac. This is
            % desirable for NSG integration
            tmpopt = options;
            if ~all([isempty(timefreq_phase{ichan_phase}),isempty(timefreq_amp{ichan_amp})])
                if  all([~isempty(timefreq_phase{ichan_phase}),~isempty(timefreq_amp{ichan_amp})])
                    tmpopt = [options 'alltfXstr' timefreq_phase{ichan_phase} 'alltfYstr' timefreq_amp{ichan_amp}] ;
                elseif isempty(timefreq_amp{ichan_amp})
                    tmpopt = [options 'alltfXstr' timefreq_phase{ichan_phase}] ;
                elseif isempty(timefreq_phase{ichan_phase})
                    tmpopt = [options 'alltfYstr' timefreq_amp{ichan_amp}] ;
                end
            end
            
            [~, ~, freqs1, freqs2, alltfX, alltfY,~, pacstruct, tfXtimes, tfYtimes] = eeg_pac(X, Y, EEG.srate,  tmpopt{:});
            
            if all([isempty(timefreq_phase{ichan_phase}),isempty(timefreq_amp{ichan_amp})])
                % populating  phase cell
                timefreq_phase{ichan_phase}.timesout = tfXtimes;
                timefreq_phase{ichan_phase}.freqs    = freqs1;
                timefreq_phase{ichan_phase}.alltf    = alltfX;
                
                % populating  phase cell
                timefreq_amp{ichan_amp}.timesout = tfYtimes;
                timefreq_amp{ichan_amp}.freqs    = freqs2;
                timefreq_amp{ichan_amp}.alltf    = alltfY;
                
            elseif isempty(timefreq_amp{ichan_amp})
                % populating  amp cell
                timefreq_amp{ichan_amp}.timesout = tfYtimes;
                timefreq_amp{ichan_amp}.freqs    = freqs2;
                timefreq_amp{ichan_amp}.alltf    = alltfY;
                
            elseif isempty(timefreq_phase{ichan_phase})
                % populating  phase cell
                timefreq_phase{ichan_phase}.timesout = tfXtimes;
                timefreq_phase{ichan_phase}.freqs    = freqs1;
                timefreq_phase{ichan_phase}.alltf    = alltfX;                
            end            
            % ---
   
            ChanIndxExist = [];
            if isfield(EEG.etc,'eegpac') && ~isempty(EEG.etc.eegpac)
                ChanIndxExist = find(cell2mat(cellfun(@(x) all(x==[indexfreqs1(ichan_phase) indexfreqs2(ichan_amp)]), {EEG.etc.eegpac.dataindx}, 'UniformOutput', 0)));
            end
            
            if ~isempty(ChanIndxExist)
                EEG.etc.eegpac(ChanIndxExist).(g.method) = pacstruct.(g.method);
                
            elseif ~isfield(EEG.etc.eegpac,'dataindx')
                EEG.etc.eegpac(1).(g.method) = pacstruct.(g.method);
                EEG.etc.eegpac(1).dataindx   = [indexfreqs1(ichan_phase),indexfreqs2(ichan_amp)] ;
                EEG.etc.eegpac(1).datatype   = datatype;
                EEG.etc.eegpac(1).params     = pacstruct.params;
                
                EEG.etc.eegpac(1).labels = {};
                if  EEG.etc.eegpac(1).datatype == 1
                    if ~isempty(EEG.chanlocs) 
                     EEG.etc.eegpac(1).labels = {EEG.chanlocs(indexfreqs1(ichan_phase)).labels EEG.chanlocs(indexfreqs2(ichan_amp)).labels};
                    else
                      EEG.etc.eegpac(1).labels =  EEG.etc.eegpac(1).dataindx;  
                    end
                end
                c = c+1;
            else
                EEG.etc.eegpac(c).(g.method) = pacstruct.(g.method);
                EEG.etc.eegpac(c).dataindx   = [indexfreqs1(ichan_phase),indexfreqs2(ichan_amp)] ;
                EEG.etc.eegpac(c).datatype   = datatype;
                EEG.etc.eegpac(c).params     = pacstruct.params;
                
                if  EEG.etc.eegpac(c).datatype == 1
                    if ~isempty(EEG.chanlocs) 
                     EEG.etc.eegpac(c).labels = {EEG.chanlocs(indexfreqs1(ichan_phase)).labels EEG.chanlocs(indexfreqs2(ichan_amp)).labels};
                    else
                        EEG.etc.eegpac(c).labels = EEG.etc.eegpac(c).dataindx;
                    end
                end
                c = c+1;
            end
        end
    end
end

% Sorting fields stuff 
tmpval = setdiff( fieldnames(EEG.etc.eegpac),{'dataindx'    'datatype'  'labels'  'params'})';
EEG.etc.eegpac = orderfields(EEG.etc.eegpac, {'dataindx'    'datatype'  'labels'  'params' tmpval{:}});
com = sprintf('EEG = pop_pac(EEG,''%s'',[%s],[%s],[%s],[%s],%s);',pooldata,num2str([freqs1(1) freqs1(end)]),num2str([freqs2(1) freqs2(end)]),num2str(indexfreqs1),num2str(indexfreqs2), vararg2str(options(5:end)));
else
    %%%%%%%%%%%%%%%%%%%%%%
    %%% NSG Submission %%%
    %%%%%%%%%%%%%%%%%%%%%%
    try
        nsg_info;  % get information on where to create the temporary file
    catch
        error('Plugin nsgportal needs to be in the MATLAB path');
    end
    
    %  Section 1: Create temporary folder and save data
    tmpJobPath = fullfile(outputfolder, 'pactmp');
    if exist(tmpJobPath,'dir'), rmdir(tmpJobPath,'s'); end
    mkdir(tmpJobPath);
    
    % Save data in temporary folder previously created.
    % Here you may change the file name to match the one in the script you will run in NSG
    pop_saveset(EEG,'filename', EEG.filename, 'filepath', tmpJobPath);
    
    % Copy toolbox to folder. temporary until updated in NSG
    pactoolfolder = which('pop_pac.m');
    pacpath = fileparts(pactoolfolder);
    copyfile(pacpath,tmpJobPath);
    
    %  Section 2
    %  Manage m-file to be executed in NSG
    %  Write m-file to be run in NSG.
    %  Options defined in plugin are written into the file
    pac_singlesubj_writejobfile
    
    % Section 3
    % Submit job to NSG
    pop_nsg('run',tmpJobPath,'filename', 'pacnsg_job.m', 'jobid', g.jobid,'runtime', g.runtime);
    display([char(10) 'PACTools job (jobID:'  g.jobid ') has been submitted to NSG' char(10) ...
                      'Copy or keep in mind the jobID assigned to this job to retreive the results later on.' char(10)...
                      'You may follow the status of your job through pop_nsg'...
        char(10)]);
    rmdir(tmpJobPath,'s');
    return;  
end
end