class catalog_preview::examples::unquoted_file_mode {

  file { '/tmp/unquoted_file_mode_test.file' :
    ensure => present,
    mode   => 600,
  }

}
