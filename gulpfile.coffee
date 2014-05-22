###*
Copyright 2014 Joukou Ltd

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
###

gulp        = require( 'gulp' )
plugins     = require( 'gulp-load-plugins' )( lazy: false )

gulp.task( 'clean', ->
  gulp.src( 'dist', read: false )
    .pipe( plugins.rimraf( force: true ) )
    .on( 'error', plugins.util.log )
)

gulp.task( 'coffee', ->
  gulp.src( 'src/**/*.coffee' )
    .pipe( plugins.coffee( bare: true, sourceMap: true ) )
    .pipe( gulp.dest( 'dist' ) )
)

gulp.task( 'default', [ 'coffee' ] )
