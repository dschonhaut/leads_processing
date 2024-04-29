function outfile = save_mask_brainstem(aparcf, in_dir, out_dir, overwrite, verbose)
    % Load the aparc+aseg and save the brainstem mask
    %
    % Usage
    % -----
    % >> save_mask_brainstem(aparcf, in_dir, out_dir, overwrite, verbose)
    %
    % Parameters
    % ----------
    % aparcf : char or str array
    %   Path to the aparc+aseg.nii file
    % in_dir : char or str array
    %   The input directory. If aparcf is empty, this is where the
    %   function looks for the aparc+aseg.nii file. This parameter is
    %   disregarded if aparcf is not empty
    % out_dir : char or str array
    %   The output directory. If out_dir is empty, the mask is saved in
    %   the same directory as the aparc+aseg.nii file
    % overwrite : logical, optional
    %   If true, overwrite existing file
    % verbose : logical, optional
    %   If true, print diagnostic information
    %
    % Files created
    % -------------
    % - <out_dir>/<scan_tag>_mask-brainstem.nii
    % ------------------------------------------------------------------
    arguments
        aparcf {mustBeText} = ''
        in_dir {mustBeText} = ''
        out_dir {mustBeText} = ''
        overwrite logical = false
        verbose logical = true
    end

    % Define aparc index for the brainstem
    mask_idx = 16;

    % Format inputs
    [aparcf, out_dir] = format_mask_inputs(aparcf, in_dir, out_dir);
    scan_tag = get_scan_tag(aparcf);

    % Save the mask
    outfile = fullfile(out_dir, append(scan_tag, '_mask-brainstem.nii'));
    nii_labels_to_mask(aparcf, mask_idx, outfile, overwrite, verbose);
end
