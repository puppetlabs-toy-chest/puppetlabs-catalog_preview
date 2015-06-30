class catalog_preview::examples::function_call_without_parans {

  $my_files = { '/tmp/create_resources_example.file' => { ensure => present } } 

  create_resources  'file', $my_files 
 
}
