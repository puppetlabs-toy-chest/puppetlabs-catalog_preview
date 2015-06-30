class catalog_preview::examples::empty_string_defaults (
   $parameter_to_check = ''
) {
  if $parameter_to_check {
    $parameter_to_check_real = $parameter_to_check
  } else {
    $parameter_to_check_real = 'default value'
  }
}
