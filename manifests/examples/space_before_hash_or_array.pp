class catalog_preview::examples::space_before_hash_or_array {

  $array = [ 'one', 'two' ]
  $hash  = {  key1 => 'val1', key2 => 'val2' }

  notify { $array [1] : } 
  notify { $hash [key1] : }

}
