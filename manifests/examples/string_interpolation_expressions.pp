class catalog_preview::examples::string_interpolation_expressions {

  $x = 4

  $y = "${x + 3}" 

  notify { $y : }

}
