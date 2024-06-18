function outfiles = process_single_pet(pet_dir, overwrite, raw_petf)
    % Process a single PET scan through all the processing steps.
    %
    % Overview
    % --------
    % 1.  Reset PET origin to the midpoint along each axis.
    % 2.  Coregister and reslice PET to the nu.nii
    % 3.  Calculate reference region means, and save voxelwise PET SUVR
    %     images in native MRI space
    % 4.  Warp PET SUVRs to MNI space using the forward deformation
    %     field from MRI segmentation
    % 5.  Linearly transform PET SUVRs to MNI space using the affine
    %     transform estimated for the nu.nii
    %
    % Usage
    % -----
    % outfiles = process_single_pet(pet_dir, overwrite)
    %
    % Parameters
    % ----------
    % pet_dir : string
    %     The directory containing PET scan data.
    % overwrite : logical
    %     Flag to overwrite existing processed files.
    %
    % Returns
    % -------
    % outfiles : struct
    %     Struct array with paths to each output file
    % ------------------------------------------------------------------
    arguments
        pet_dir {mustBeFolder}
        overwrite logical = false
        raw_petf {mustBeText} = ''
    end

    % ------------------------------------------------------------------
    % Hard-code a list amyloid PET tracers
    amyloid_tracers = {'FBB', 'FBP', 'FLUTE', 'NAV', 'PIB'};

    % ------------------------------------------------------------------
    % Get scan info
    pet_dir = abspath(pet_dir);
    pet_tag = get_scan_tag(pet_dir);
    [~, tracer] = parse_scan_tag(pet_tag);
    tracer_is_amyloid = ismember(tracer, amyloid_tracers);

    mri_dir = fullfile(pet_dir, 'mri');
    mri_tag = get_scan_tag(mri_dir);

    % ------------------------------------------------------------------
    % If processing is already complete and overwrite is false, get
    % the struct of processed MRI files and return
    if processed_pet_files_exist(pet_dir) && ~overwrite
        fprintf('%s processing already complete, returning output files\n', pet_tag);
        outfiles = get_processed_pet_files(mri_dir);
        return
    end

    % ------------------------------------------------------------------
    % Start the log file
    fid = log_start(pet_dir);

    try
        % --------------------------------------------------------------
        % Print the module header
        log_append(fid, '', 0, 0);
        log_append(fid, 'START PET PROCESSING MODULE', 0, 0);
        log_append(fid, '---------------------------', 0, 0);
        log_append(fid, '', 0, 0);

        % Print path to the current code file
        log_append(fid, 'Code file:', 0, 0);
        log_append(fid, sprintf('%s.m\n', mfilename('fullpath')), 0, 0);

        % Print the input parameters
        log_append(fid, 'Input parameters:', 0, 0);
        log_append(fid, sprintf('pet_dir = %s', pet_dir), 0, 0);
        log_append(fid, sprintf('overwrite = %d', overwrite), 0, 0);
        if isempty(raw_petf)
            log_append(fid, 'raw_petf = ''''', 0, 0);
        else
            log_append(fid, sprintf('raw_petf = %s', raw_petf), 0, 0);
        end
        log_append(fid, '', 0, 0);

        % --------------------------------------------------------------
        % Find the raw PET scan and copy it in to the processed directory
        if isempty(raw_petf)
            raw_petf = dir(fullfile(pet_dir, 'raw', '*.nii'));
            raw_petf = abspath(fullfile({raw_petf.folder}, {raw_petf.name}));
        end
        outfiles.pet = fullfile(pet_dir, append(pet_tag, '.nii'));
        if length(raw_petf) == 1
            copyfile(raw_petf{1}, outfiles.pet);
            log_append(fid, sprintf( ...
                ['- Copying raw PET .nii file to the processed scan directory\n' ...
                 '            %s ->\n            %s'], ...
                basename(raw_petf{1}), basename(outfiles.pet) ...
            ));
        else
            error('Expected 1 raw PET scan, found %d', length(raw_petf));
        end

        % --------------------------------------------------------------
        % Initialize SPM jobman and PET parameter defaults
        spm_jobman('initcfg');
        spm('defaults','PET');

        % --------------------------------------------------------------
        % Reset origin to axis midpoint
        outfiles.pet = reset_origin_axis_midpoint(outfiles.pet, fid);

        % --------------------------------------------------------------
        % Coregister and reslice PET to the nu.nii
        mri_files = get_freesurfer_files(mri_dir);
        outfiles.rpet = coreg_reslice_pet_to_mri(outfiles.pet, mri_files.nu, fid, overwrite);

        % --------------------------------------------------------------
        % Save SUVRs in native MRI space
        outfiles = catstruct( ...
            outfiles, save_pet_suvrs(outfiles.rpet, mri_dir, fid, overwrite) ...
        );
        [ref_regions, suvr_files] = get_suvr_files(pet_dir);

        % --------------------------------------------------------------
        % Extract ROI means from native MRI space PET SUVRs

        % Get paths to any mask files that we want to extract
        maskfs = [];
        for ii = 1:length(ref_regions.masks)
            masks = ref_regions.masks(ii);
            maskfs = [maskfs; ...
                cellfun( ...
                    @(x) fullfile(mri_dir, append(mri_tag, '_mask-', x, '.nii')), ...
                    strtrim(split(masks, ';')), ...
                    'UniformOutput', false ...
                );
            ];
        end
        maskfs = unique(maskfs);

        % Get the CSV file that lists FreeSurfer ROIs to extract
        code_dir = fileparts(fileparts(mfilename('fullpath')));
        fsroif = fullfile(code_dir, 'config', append('fsroi_list_', tracer, '.csv'));

        % Run the ROI extractions
        run_pet_roi_extractions( ...
            suvr_files, maskfs, mri_files.aparc, fsroif, fid, overwrite ...
        );

        % --------------------------------------------------------------
        % For amyloid PET, calculate the cortical summary SUVR and
        % its corresponding CL value for each reference region
        if tracer_is_amyloid
            outfiles.cortical_summary = fullfile( ...
                pet_dir, append(pet_tag, '_amyloid-cortical-summary.csv') ...
            );
            cortical_summary_maskf = fullfile( ...
                mri_dir, append(mri_tag, '_mask-amyloid-cortical-summary.nii') ...
            );
            calculate_centiloids( ...
                suvr_files, ...
                cortical_summary_maskf, ...
                outfiles.cortical_summary, ...
                fid, ...
                overwrite ...
            );
        end

        % --------------------------------------------------------------
        % Warp the nu.nii to MNI space using the forward deformation field
        % estimated during segmentation
        mri_files.y = fullfile(mri_dir, append('y_', mri_tag, '_nu.nii'));
        outfiles = catstruct( ...
            outfiles, apply_warp_to_mni(suvr_files, mri_files.y, fid, overwrite) ...
        );

        % --------------------------------------------------------------
        % Affine transform the nu.nii to MNI space
        mri_files.atf = fullfile(mri_dir, append('atf_', mri_tag, '_nu.mat'));
        outfiles = catstruct( ...
            outfiles, apply_affine_to_mni(suvr_files, mri_files.atf, fid, overwrite) ...
        );

        % --------------------------------------------------------------
        % Identify and log any missing processed files
        log_append(fid, '- Checking for expected output files');
        if processed_pet_files_exist(pet_dir)
            log_append(fid, '  * Found all expected output files');
        else
            outfiles_expected = cellvec(get_processed_pet_files(pet_dir));
            outfiles_missing = outfiles_expected(~cellfun(@isfile, outfiles_expected));
            n_missing = length(outfiles_missing);
            if n_missing == 1
                log_append(fid, '  * WARNING: Missing 1 expected output');
            else
                log_append( ...
                    fid, ...
                    sprintf('  * WARNING: Missing %d expected outputs', n_missing) ...
                );
            end
            cellfun(@(x) log_append(fid, sprintf('    - %s', x)), outfiles_missing);
        end

        % --------------------------------------------------------------
        % Print the module footer
        log_append(fid, '', 0, 0);
        log_append(fid, '-------------------------', 0, 0);
        log_append(fid, 'END PET PROCESSING MODULE', 0, 0);
        log_append(fid, '', 0, 0);

        % --------------------------------------------------------------
        % Close the log file
        log_close(fid);
    catch ME
        % Print the error message
        log_append(fid, '!! ERROR !!');
        log_append(fid, getReport(ME, 'extended', 'hyperlinks', 'off'), 0, 0);

        % Close the log file
        log_append(fid, '\nClosing log file early due to error', 0, 0);
        log_close(fid);

        % Rethrow the error
        rethrow(ME);
    end
end
