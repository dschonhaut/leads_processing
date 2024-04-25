function process_mri_post_freesurfer(mri_dir, segment_brainstem, overwrite, verbose)
    % High-level function to process MRI after FreeSurfer has been run
    % ------------------------------------------------------------------
    arguments
        mri_dir {mustBeText}
        segment_brainstem logical = true
        overwrite logical = false
        verbose logical = true
    end

    % Format inputs
    mri_dir = abspath(mri_dir);
    subj_dir = fileparts(mri_dir);
    scan_tag = get_scan_tag(mri_dir);

    % Copy FreeSurfer files to the subject's processed mri directory
    % and convert them from .mgz to .nii
    copy_convert_freesurfer(mri_dir, segment_brainstem, overwrite, verbose);
    if segment_brainstem
        [~, nuf, aparcf, brainstemf] = get_freesurfer_files(mri_dir, 'nii', segment_brainstem);
        mri_files = {nuf, aparcf, brainstemf};
    else
        [~, nuf, aparcf] = get_freesurfer_files(mri_dir, 'nii', segment_brainstem);
        mri_files = {nuf, aparcf};
    end

    % Reset origin to center-of-mass (note this step overwrites the
    % input image files)
    mri_reset_origin_com(mri_files,verbose);

    % If MRI is not baseline, coregister it to the baseline MRI
    if ~is_baseline_mri(mri_dir)
        baseline_mri_dir = get_baseline_mri_dir(mri_dir);
        mri_coregister(mri_files, baseline_mri_dir);
    end

    % Segment MRI, save forward and inverse deformation fields
    segment_mri(mri_dir, overwrite, verbose);

    % Warp MRI to MNI space
    warp_to_mni(nuf, mri_dir, overwrite, verbose);

    % Calculate affine transform from MRI native space to MNI
    affine_mri_to_mni(mri_dir, overwrite, verbose);

    % Save out mask files used as reference regions or target ROIs.
    save_aparc_roi_masks(mri_dir, overwrite, verbose);
end



