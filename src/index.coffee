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

fs        = require( 'fs' )
path      = require( 'path' )
async     = require( 'async' )
request   = require( 'request' )
{ exec }  = require( 'child_process' )

module.exports = ( gulp, plugins ) ->
  self =
    isCI: ->
      process.env.CI is 'true'

    getPackage: ->
      require( path.join( process.cwd(), 'package.json' ) )

    getName: ->
      self.getPackage().name

    getShortName: ->
      self.getName().substring( 7 )

    getVersion: ->
      self.getPackage().version

    getSha: ->
      process.env.CIRCLE_SHA1

    getBuildNum: ->
      process.env.CIRCLE_BUILD_NUM

    getArtifactsDir: ->
      process.env.CIRCLE_ARTIFACTS

    getZipFilenameSuffix: ->
      "-#{self.getVersion()}-#{self.getSha()}-#{self.getBuildNum()}.zip"

    getPackageZipFilename: ->
      "#{self.getName()}#{self.getZipFilenameSuffix()}"

    getDocZipFilename: ->
      "#{self.getName()}doc#{self.getZipFilenameSuffix()}"

    getDeploymentEnvironment: ->
      switch process.env.CIRCLE_BRANCH
        when 'master'
          'production'
        when 'develop'
          'staging'
        else
          throw new Error( "Invalid branch #{process.env.CIRCLE_BRANCH} for deployment" )

    getDeploymentServers: ->
      switch self.getDeploymentEnvironment()
        when 'production'
          [
            'akl1.joukou.com'
            'akl2.joukou.com'
            'akl3.joukou.com'
          ]
        when 'staging'
          [
            'akl1.staging.joukou.com'
            'akl2.staging.joukou.com'
            'akl3.staging.joukou.com'
          ]
        else
          []

    getPackageDeploymentType: ->
      switch self.getName()
        when 'joukou-control'
          'www'
        else
          'node'

    getPackageDeploymentUser: ->
      switch self.getPackageDeploymentType()
        when 'www'
          'www-data'
        when 'node'
          'node'
        else
          throw new Error( "Invalid deployment type #{self.getDeploymentType()}" )

    getPackageDeploymentDomain: ->
      switch self.getName()
        when 'joukou-control'
          switch self.getDeploymentEnvironment()
            when 'production'
              'joukou.com'
            else
              'staging.joukou.com'
        else
          switch self.getDeploymentEnvironment()
            when 'production'
              "#{self.getShortName()}.joukou.com"
            else
              "staging-#{self.getShortName()}.joukou.com"

    getDocDeploymentDomain: ->
      switch self.getDeploymentEnvironment()
        when 'production'
          "#{self.getShortName()}doc.joukou.com"
        when 'staging'
          "staging-#{self.getShortName()}doc.joukou.com"
        else
          throw new Error( 'Invalid deployment environment' )

    getPackageDeploymentRemotePath: ->
      "/var/#{self.getPackageDeploymentType()}/#{self.getPackageDeploymentDomain()}"

    getDocDeploymentRemotePath: ->
      "/var/www/#{self.getDocDeploymentDomain()}"

    getDeploymentScpCommand: ( { host, user, filename } ) ->
      [
        'scp'
        '-o'
        'IdentityFile=/home/ubuntu/.ssh/id_joukou.com'
        '-o'
        'ControlMaster=no'
        path.join( self.getArtifactsDir(), filename )
        "#{user}@#{host}:#{path.join( '/tmp', filename )}"
      ].join( ' ' )

    getPackageDeploymentScpCommand: ( { host } ) ->
      self.getDeploymentScpCommand( host: host, user: self.getPackageDeploymentUser(), filename: self.getPackageZipFilename() )

    getDocDeploymentScpCommand: ( { host } ) ->
      self.getDeploymentScpCommand( host: host, user: 'www-data', filename: self.getDocZipFilename() )

    doPackageDeploymentUpload: ( done ) ->
      async.each( self.getDeploymentServers(), ( host, next ) ->
        exec( self.getPackageDeploymentScpCommand( host: host ), ( err, stdout, stderr ) ->
          if err
            plugins.util.log( stdout )
            plugins.util.log( stderr )
          next( err )
        )
        return
      , done )
      return

    doDocDeploymentUpload: ( done ) ->
      async.each( self.getDeploymentServers(), ( host, next ) ->
        exec( self.getDocDeploymentScpCommand( host: host ), ( err, stdout, stderr ) ->
          if err
            plugins.util.log( stdout )
            plugins.util.log( stderr )
          next( err )
        )
        return
      , done )
      return

    doPackageDeploymentCommands: ( done ) ->
      async.each( self.getDeploymentServers(), ( host, next ) ->
        command = [
          "rm -rf #{path.join( self.getPackageDeploymentRemotePath(), '*' )}"
          "unzip -qq -o /tmp/#{self.getPackageZipFilename()} -d #{self.getPackageDeploymentRemotePath()}"
        ]

        if self.getPackageDeploymentType() is 'node'
          command.unshift( "sudo stop #{self.getPackageDeploymentDomain()}" )
          command.push( "sudo start #{self.getPackageDeploymentDomain()}" )

        plugins.ssh.exec(
          command: command
          sshConfig:
            host: host
            port: 22
            username: self.getPackageDeploymentUser()
            privateKey: fs.readFileSync( '/home/ubuntu/.ssh/id_joukou.com' ).toString()
        )
        next()       
      , done )
      return

    doDocDeploymentCommands: ( done ) ->
      async.each( self.getDeploymentServers(), ( host, next ) ->
         plugins.ssh.exec(
          command: [
            "rm -rf #{path.join( self.getDocDeploymentRemotePath(), '*' )}"
            "unzip -qq -o /tmp/#{self.getDocZipFilename()} -d #{self.getDocDeploymentRemotePath()}"
          ]
          sshConfig:
            host: host
            port: 22
            username: 'www-data'
            privateKey: fs.readFileSync( '/home/ubuntu/.ssh/id_joukou.com' ).toString()
        )
        next()       
      , done )
      return

    doPackageDeploymentNotification: ->
      ( done ) ->
        request(
          uri: 'https://api.flowdock.com/v1/messages/team_inbox/87d6d03d770e3ea007f7fe747fede5f4'
          method: 'POST'
          json:
            source: 'Circle'
            from_address: 'deploy+ok@joukou.com'
            subject: "Success: deployment of #{self.getName()} to #{self.getDeploymentEnvironment()} from build \##{self.getBuildNum()}"
            content: """
                     <b>#{self.getName()}</b> deployed to <a href="https://#{self.getPackageDeploymentDomain()}">#{self.getPackageDeploymentDomain()}</a>
                     """
            from_name: ''
            # Flowdock replaces "-" with "" and " " with "-". So to actually get
            # "-" we need " ".
            project: self.getName().replace( '-', ' ')
            tags: [ '#deploy', "\##{self.getDeploymentEnvironment()}" ]
            link: "https://#{self.getPackageDeploymentDomain()}"
        , ( err , response, body ) ->
          done( err )
        )
        return

    doDocDeploymentNotification: ->
      ( done ) ->
        request(
          uri: 'https://api.flowdock.com/v1/messages/team_inbox/87d6d03d770e3ea007f7fe747fede5f4'
          method: 'POST'
          json:
            source: 'Circle'
            from_address: 'deploy+ok@joukou.com'
            subject: "Success: deployment of #{self.getName()}doc to #{self.getDocDeploymentDomain()} from build \##{self.getBuildNum()}"
            content: """
                     <b>#{self.getName()}doc</b> deployed to <a href="https://#{self.getDocDeploymentDomain()}">#{self.getDocDeploymentDomain()}</a>
                     """
            from_name: ''
            # Flowdock replaces "-" with "" and " " with "-". So to actually get
            # "-" we need " ".
            project: self.getName().replace( '-', ' ')
            tags: [ '#deploy', "\##{self.getDeploymentEnvironment()}", "#documentation" ]
            link: "https://#{self.getDocDeploymentDomain()}"
        , ( err, response, body ) ->
          done( err )
        )
        return
