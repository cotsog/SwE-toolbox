function [SwE] = swe_contrasts(SwE,Ic)
% Fills in SwE.xCon and writes con_????.img, ess_????.img and SwE?_????.img
% FORMAT [SwE] = SwE_contrasts(SwE,Ic)
%
% SwE - SwE data structure
% Ic  - indices of xCon to compute
% Modified version of spm_contrasts adapted for the SwE toolbox
% By Bryan Guillaume

% Temporary SwE variable to check for any changes to SwE. We want to avoid
% always having to save SwE.mat unless it has changed, because this is
% slow. A side benefit is one can look at results with just read
% privileges.
%--------------------------------------------------------------------------
tmpSwE = SwE;

%-Get and change to results directory
%--------------------------------------------------------------------------
try
    cd(SwE.swd);
end

%-Get contrast definitions (if available)
%--------------------------------------------------------------------------
try
    xCon = SwE.xCon;
catch
    xCon = [];
end

%-Set all contrasts by default
%--------------------------------------------------------------------------
if nargin < 2
    Ic   = 1:length(xCon);
end

%-Map parameter files
%--------------------------------------------------------------------------
    
%-OLS estimators and covariance estimates
%--------------------------------------------------------------------------
Vbeta = SwE.Vbeta;
Vcov_beta = SwE.Vcov_beta;
dof_type = SwE.dof.dof_type;
if dof_type
    Vcov_beta_g = SwE.Vcov_beta_g;
else
    dof_cov = SwE.dof.dof_cov;
end

%-Compute & store contrast parameters, contrast/ESS images, & SwE images
%==========================================================================
spm('Pointer','Watch')
XYZ   = SwE.xVol.XYZ;
S=size(XYZ,2);
for i = 1:length(Ic)
     
    %-Canonicalise contrast structure with required fields
    %----------------------------------------------------------------------
    ic = Ic(i);
    %-Write contrast images?
    %======================================================================
    if isempty(xCon(ic).Vspm)
        Q = cumprod([1,SwE.xVol.DIM(1:2)'])*XYZ - ...
            sum(cumprod(SwE.xVol.DIM(1:2)'));
        Co=xCon(ic).c;
        xCon(ic).eidf=rank(Co);
        % detect the indices of the betas of interest
        if size(Co,2)==1
            ind = find(Co ~= 0);
        else
            ind = find(any(Co'~=0));
        end
        nCov_beta = (size(Co,1)+1)*size(Co,1)/2;

        % if the Co is a vector, then create Co * Beta (Vcon)
        if size(Co,2)==1
            %-Compute contrast
            %------------------------------------------------------
            fprintf('\t%-32s: %30s',sprintf('contrast image %2d',ic),...
                '...computing');                                %-#
            str   = 'contrast computation';
            spm_progress_bar('Init',100,str,'');            
            V      = Vbeta(ind);
            cB     = zeros(1,S);
            for j=1:numel(V)
                cB = cB + Co(ind(j)) * spm_get_data(V(j),XYZ);
                spm_progress_bar('Set',100*(j/numel(V)));
            end
            spm_progress_bar('Clear')            
            %-Prepare handle for contrast image
            %------------------------------------------------------
            xCon(ic).Vcon = struct(...
                'fname',  sprintf('con_%04d.img',ic),...
                'dim',    SwE.xVol.DIM',...
                'dt',     [spm_type('float32') spm_platform('bigend')],...
                'mat',    SwE.xVol.M,...
                'pinfo',  [1,0,0]',...
                'descrip',sprintf('SwE contrast - %d: %s',ic,xCon(ic).name));
            
            %-Write image
            %------------------------------------------------------
            tmp = NaN(SwE.xVol.DIM');
            tmp(Q) = cB;            
            xCon(ic).Vcon = spm_write_vol(xCon(ic).Vcon,tmp);
                    
            clear tmp
            fprintf('%s%30s\n',repmat(sprintf('\b'),1,30),sprintf(...
                        '...written %s',spm_file(xCon(ic).Vcon.fname,'filename')))%-#

        else
            %-Compute contrast
            %------------------------------------------------------
            fprintf('\t%-32s: %30s',sprintf('contrast image %2d',ic),...
                '...computing');                                %-#
            str   = 'contrast computation';
            spm_progress_bar('Init',100,str,'');
            V      = Vbeta(ind);
            cB     = zeros(size(Co,2),S);
            for j=1:numel(V)
                cB = cB + Co(ind(j),:)' * spm_get_data(V(j),XYZ);
                spm_progress_bar('Set',100*(j/numel(V)));
            end 
            spm_progress_bar('Clear')
        end
        
        
        %-Write inference SwE
        %======================================================================
        
        %-compute the contrasted beta covariances and edof for the contrast
        fprintf('\t%-32s: %30s',sprintf('spm{%c} image %2d',xCon(ic).STAT,ic),...
            '...computing');                                %-#
        str   = 'contrasted beta covariance computation';
        spm_progress_bar('Init',100,str,'');            

        it = 0;
        it2 = 0;
        cCovBc = zeros(size(Co,2)*(size(Co,2)+1)/2,S);
        if dof_type
            cCovBc_g = zeros(size(Co,2)*(size(Co,2)+1)/2,S,SwE.Gr.nGr);
        else
            xCon(ic).edf = sum(SwE.dof.nSubj_dof(unique(SwE.dof.iBeta_dof(ind))) - ...
            SwE.dof.pB_dof(unique(SwE.dof.iBeta_dof(ind)))); 
        end
        for j = 1:size(Co,1)
            for jj = j:size(Co,1)
                it = it + 1;
                if any(j == ind) & any(jj == ind)
                    it2 = it2+1;
                    weight = Co(j,:)'*Co(jj,:);
                    if (j==jj)
                        weight = weight + weight';
                    end
                    weight = weight(tril(ones(size(Co,2)))==1);
                    cCovBc = cCovBc + weight * spm_get_data(Vcov_beta(it),XYZ);
                    if dof_type
                        for g = 1:SwE.Gr.nGr                            
                            cCovBc_g(:,:,g) = cCovBc_g(:,:,g) + weight *...
                                spm_get_data(Vcov_beta_g((g-1)*nCov_beta+it),XYZ);
                            spm_progress_bar('Set',100*((it2-1+g/SwE.Gr.nGr)/length(ind)/(length(ind)+1)*2));
                        end
                    end
                    spm_progress_bar('Set',100*(it2/length(ind)/(length(ind)+1)*2));
                end
            end
        end
        spm_progress_bar('Clear')

        str   = 'spm computation';
        spm_progress_bar('Init',100,str,'');         
        switch(xCon(ic).STAT)
            case 'T'                                 %-Compute spm{t} image
                %----------------------------------------------------------
                Z = cB ./ sqrt(cCovBc);
                spm_progress_bar('Set',100*(0.1));
                if dof_type                   
                    tmp = 0;
                    for g = 1:SwE.Gr.nGr
                        tmp = tmp + cCovBc_g(:,:,g).^2/SwE.dof.edof_Gr(g);
                        spm_progress_bar('Set',100*(g/SwE.Gr.nGr/10+0.1));
                    end
                    clear cCovBc_g
                    edf = cCovBc.^2 ./ tmp;
                    spm_progress_bar('Set',100*(0.2));
                    % transform into Z-scores image
                    Z = -norminv(tcdf(-Z,edf)); 
                    %Z = -log10(1-spm_Tcdf(Z,edf)); %transfo into -log10(p)
                    spm_progress_bar('Set',100);
                else
                    % transform into Z-scores image
                    Z = -norminv(tcdf(-Z,xCon(ic).edf)); 
                    % transform into -log10(p-values) image
                    %Z = -log10(1-spm_Tcdf(Z,xCon(ic).edf));
                    spm_progress_bar('Set',100);
                end               
                
            case 'F'                                 %-Compute spm{F} image
                %---------------------------------------------------------
                if size(Co,2)==1
                    Z = abs(cB ./ sqrt(cCovBc));
                    spm_progress_bar('Set',100*(0.1));
                    if dof_type
                        tmp = 0;
                        for g = 1:SwE.Gr.nGr
                            tmp = tmp + cCovBc_g(:,:,g).^2/SwE.dof.edof_Gr(g);
                            spm_progress_bar('Set',100*(g/SwE.Gr.nGr/10+0.1));
                        end
                        clear cCovBc_g
                        edf = cCovBc.^2 ./ tmp;
                        spm_progress_bar('Set',100*(3/4));
                        % transform into X-scores image
                        Z = (norminv(spm_Tcdf(-Z,edf))).^2;
                        % transform into -log10(p-values) image
                        %Z = -log10(1-spm_Fcdf(Z,1,edf));
                        spm_progress_bar('Set',100);
                    else
                        % transform into X-scores image
                        Z = (norminv(spm_Tcdf(-Z,xCon(ic).edf))).^2;
                        % transform into -log10(p-values) image
                        %Z = -log10(1-spm_Fcdf(Z,1, xCon(ic).edf));
                        spm_progress_bar('Set',100);
                    end
                else
                    Z   = zeros(1,S);
                    if dof_type
                        edf = zeros(1,S);
                    end
                    for iVox=1:S
                        cCovBc_vox = zeros(size(Co,2));
                        cCovBc_vox(tril(ones(size(Co,2)))==1) = cCovBc(:,iVox);
                        cCovBc_vox = cCovBc_vox + cCovBc_vox' - diag(diag(cCovBc_vox));
                        Z(iVox) = cB(:,iVox)' / cCovBc_vox * cB(:,iVox);                     
                        if dof_type
                            tmp = 0;
                            for g = 1:SwE.Gr.nGr
                                cCovBc_g_vox = zeros(size(Co,2));
                                cCovBc_g_vox(tril(ones(size(Co,2)))==1) = cCovBc_g(:,iVox,g);
                                cCovBc_g_vox = cCovBc_g_vox + cCovBc_g_vox' - diag(diag(cCovBc_g_vox));
                                tmp = tmp + (trace(cCovBc_g_vox^2) + (trace(cCovBc_g_vox))^2)/...
                                    SwE.dof.edof_Gr(g);                              
                            end
                            edf(iVox)=(trace(cCovBc_vox^2) + (trace(cCovBc_vox))^2) / tmp;
                            
                        end
                        spm_progress_bar('Set',100*(iVox/S/2));
                    end
                    if dof_type
                        clear cCovBc_g
                        Z = Z .*(edf-xCon(ic).eidf+1)./edf/xCon(ic).eidf;
                        % transform into X-scores image
                        Z = chi2inv(spm_Fcdf(Z,xCon(ic).eidf,edf));
                        % transform into -log10(p-values) image
                        %Z = -log10(1-spm_Fcdf(Z,xCon(ic).eidf,edf));
                    else
                        Z = Z *(xCon(ic).edf -xCon(ic).eidf+1)/xCon(ic).edf/xCon(ic).eidf;
                        % transform into X-scores image
                        Z = chi2inv(spm_Fcdf(Z,xCon(ic).eidf,xCon(ic).edf));
                        % transform into -log10(p-values) image
                        %Z = -log10(1-spm_Fcdf(Z,xCon(ic).eidf,xCon(ic).edf));
                        spm_progress_bar('Set',100);
                    end
                end
        end
        spm_progress_bar('Clear')
        clear cCovBc cB tmp
        
        
        %-Write SwE - statistic image & edf image if needed
        %------------------------------------------------------------------
        fprintf('%s%30s',repmat(sprintf('\b'),1,30),'...writing');      %-#

        xCon(ic).Vspm = struct(...
            'fname',  sprintf('spm%c_%04d.img',xCon(ic).STAT,ic),...
            'dim',    SwE.xVol.DIM',...
            'dt',     [spm_type('float32'), spm_platform('bigend')],...
            'mat',    SwE.xVol.M,...
            'pinfo',  [1,0,0]',...
            'descrip',sprintf('spm{%c} - contrast %d: %s',...%'SwE{%c_%s} - contrast %d: %s'
           xCon(ic).STAT,ic,xCon(ic).name));% xCon(ic).STAT,str,ic,xCon(ic).name));
        xCon(ic).Vspm = spm_create_vol(xCon(ic).Vspm);

        tmp           = zeros(SwE.xVol.DIM');
        tmp(Q)        = Z;
        xCon(ic).Vspm = spm_write_vol(xCon(ic).Vspm,tmp);

        clear tmp Z
        fprintf('%s%30s\n',repmat(sprintf('\b'),1,30),sprintf(...
            '...written %s',spm_str_manip(xCon(ic).Vspm.fname,'t')));   %-#
        
        if dof_type
            xCon(ic).Vedf = struct(...
                'fname',  sprintf('edf_%04d.img',ic),...
                'dim',    SwE.xVol.DIM',...
                'dt',     [16 spm_platform('bigend')],...
                'mat',    SwE.xVol.M,...
                'pinfo',  [1,0,0]',...
                'descrip',sprintf('SwE effective degrees of freedom - %d: %s',ic,xCon(ic).name));
            fprintf('%s%20s',repmat(sprintf('\b'),1,20),'...computing')%-#
            xCon(ic).Vedf = spm_create_vol(xCon(ic).Vedf);
            tmp = NaN(SwE.xVol.DIM');
            tmp(Q) = edf;
            xCon(ic).Vedf = spm_write_vol(xCon(ic).Vedf,tmp);
            
            clear tmp edf
            fprintf('%s%30s\n',repmat(sprintf('\b'),1,30),sprintf(...
                '...written %s',spm_str_manip(xCon(ic).Vedf.fname,'t')))%-#
              
        end
                           
    end % if isempty(xCon(ic).Vspm)

end % (for i = 1:length(Ic))
spm('Pointer','Arrow')

% place xCon back in SwE
%--------------------------------------------------------------------------
SwE.xCon = xCon;

% Check if SwE has changed. Save only if it has.
%--------------------------------------------------------------------------
if ~isequal(tmpSwE,SwE)
    if spm_matlab_version_chk('7') >=0
        save('SwE', 'SwE', '-V6');
    else
        save('SwE', 'SwE');
    end
end