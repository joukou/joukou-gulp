
/**
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
 */
var async, exec, fs, path, request;

fs = require('fs');

path = require('path');

async = require('async');

request = require('request');

exec = require('child_process').exec;

module.exports = function(gulp, plugins) {
  var self;
  return self = {
    isCI: function() {
      return process.env.CI === 'true';
    },
    getPackage: function() {
      return require(path.join(process.cwd(), 'package.json'));
    },
    getName: function() {
      return self.getPackage().name;
    },
    getShortName: function() {
      return self.getName().substring(7);
    },
    getVersion: function() {
      return self.getPackage().version;
    },
    getSha: function() {
      return process.env.CIRCLE_SHA1;
    },
    getBuildNum: function() {
      return process.env.CIRCLE_BUILD_NUM;
    },
    getArtifactsDir: function() {
      return process.env.CIRCLE_ARTIFACTS;
    },
    getZipFilenameSuffix: function() {
      return "-" + (self.getVersion()) + "-" + (self.getSha()) + "-" + (self.getBuildNum()) + ".zip";
    },
    getPackageZipFilename: function() {
      return "" + (self.getName()) + (self.getZipFilenameSuffix());
    },
    getDocZipFilename: function() {
      return "" + (self.getName()) + "doc" + (self.getZipFilenameSuffix());
    },
    getDeploymentEnvironment: function() {
      switch (process.env.CIRCLE_BRANCH) {
        case 'master':
          return 'production';
        case 'develop':
          return 'staging';
        default:
          throw new Error("Invalid branch " + process.env.CIRCLE_BRANCH + " for deployment");
      }
    },
    getDeploymentServers: function() {
      switch (self.getDeploymentEnvironment()) {
        case 'production':
          return ['akl1.joukou.com', 'akl2.joukou.com', 'akl3.joukou.com'];
        case 'staging':
          return ['akl1.staging.joukou.com', 'akl2.staging.joukou.com', 'akl3.staging.joukou.com'];
        default:
          return [];
      }
    },
    getPackageDeploymentType: function() {
      switch (self.getName()) {
        case 'joukou-control':
          return 'www';
        default:
          return 'node';
      }
    },
    getPackageDeploymentUser: function() {
      switch (self.getPackageDeploymentType()) {
        case 'www':
          return 'www-data';
        case 'node':
          return 'node';
        default:
          throw new Error("Invalid deployment type " + (self.getDeploymentType()));
      }
    },
    getPackageDeploymentDomain: function() {
      switch (self.getName()) {
        case 'joukou-control':
          switch (self.getDeploymentEnvironment()) {
            case 'production':
              return 'joukou.com';
            default:
              return 'staging.joukou.com';
          }
          break;
        default:
          switch (self.getDeploymentEnvironment()) {
            case 'production':
              return "" + (self.getShortName()) + ".joukou.com";
            default:
              return "staging-" + (self.getShortName()) + ".joukou.com";
          }
      }
    },
    getDocDeploymentDomain: function() {
      switch (self.getDeploymentEnvironment()) {
        case 'production':
          return "" + (self.getShortName()) + "doc.joukou.com";
        case 'staging':
          return "staging-" + (self.getShortName()) + "doc.joukou.com";
        default:
          throw new Error('Invalid deployment environment');
      }
    },
    getPackageDeploymentRemotePath: function() {
      return "/var/" + (self.getPackageDeploymentType()) + "/" + (self.getPackageDeploymentDomain());
    },
    getDocDeploymentRemotePath: function() {
      return "/var/www/" + (self.getDocDeploymentDomain());
    },
    getDeploymentScpCommand: function(_arg) {
      var filename, host, user;
      host = _arg.host, user = _arg.user, filename = _arg.filename;
      return ['scp', '-o', 'IdentityFile=/home/ubuntu/.ssh/id_joukou.com', '-o', 'ControlMaster=no', path.join(self.getArtifactsDir(), filename), "" + user + "@" + host + ":" + (path.join('/tmp', filename))].join(' ');
    },
    getPackageDeploymentScpCommand: function(_arg) {
      var host;
      host = _arg.host;
      return self.getDeploymentScpCommand({
        host: host,
        user: self.getPackageDeploymentUser(),
        filename: self.getPackageZipFilename()
      });
    },
    getDocDeploymentScpCommand: function(_arg) {
      var host;
      host = _arg.host;
      return self.getDeploymentScpCommand({
        host: host,
        user: 'www-data',
        filename: self.getDocZipFilename()
      });
    },
    doPackageDeploymentUpload: function(done) {
      async.each(self.getDeploymentServers(), function(host, next) {
        exec(self.getPackageDeploymentScpCommand({
          host: host
        }), function(err, stdout, stderr) {
          if (err) {
            plugins.util.log(stdout);
            plugins.util.log(stderr);
          }
          return next(err);
        });
      }, done);
    },
    doDocDeploymentUpload: function(done) {
      async.each(self.getDeploymentServers(), function(host, next) {
        exec(self.getDocDeploymentScpCommand({
          host: host
        }), function(err, stdout, stderr) {
          if (err) {
            plugins.util.log(stdout);
            plugins.util.log(stderr);
          }
          return next(err);
        });
      }, done);
    },
    doPackageDeploymentCommands: function(done) {
      async.each(self.getDeploymentServers(), function(host, next) {
        var command;
        command = ["rm -rf " + (path.join(self.getPackageDeploymentRemotePath(), '*')), "unzip -qq -o /tmp/" + (self.getPackageZipFilename()) + " -d " + (self.getPackageDeploymentRemotePath())];
        if (self.getPackageDeploymentType() === 'node') {
          command.unshift("sudo stop " + (self.getPackageDeploymentDomain()));
          command.push("sudo start " + (self.getPackageDeploymentDomain()));
        }
        plugins.ssh.exec({
          command: command,
          sshConfig: {
            host: host,
            port: 22,
            username: self.getPackageDeploymentUser(),
            privateKey: fs.readFileSync('/home/ubuntu/.ssh/id_joukou.com').toString()
          }
        });
        return next();
      }, done);
    },
    doDocDeploymentCommands: function(done) {
      async.each(self.getDeploymentServers(), function(host, next) {
        return plugins.ssh.exec({
          command: ["rm -rf " + (path.join(self.getDocDeploymentRemotePath(), '*')), "unzip -qq -o /tmp/" + (self.getDocZipFilename()) + " -d " + (self.getDocDeploymentRemotePath())],
          sshConfig: {
            host: host,
            port: 22,
            username: 'www-data',
            privateKey: fs.readFileSync('/home/ubuntu/.ssh/id_joukou.com').toString()
          }
        });
      }, next(), done);
    },
    doPackageDeploymentNotification: function() {
      return function(done) {
        request({
          uri: 'https://api.flowdock.com/v1/messages/team_inbox/87d6d03d770e3ea007f7fe747fede5f4',
          method: 'POST',
          json: {
            source: 'Circle',
            from_address: 'deploy+ok@joukou.com',
            subject: "Success: deployment of " + (self.getName()) + " to " + (self.getDeploymentEnvironment()) + " from build \#" + (self.getBuildNum()),
            content: "<b>" + (self.getName()) + "</b> deployed to <a href=\"https://" + (self.getPackageDeploymentDomain()) + "\">" + (self.getPackageDeploymentDomain()) + "</a>",
            from_name: '',
            project: self.getName().replace('-', ' '),
            tags: ['#deploy', "\#" + (self.getDeploymentEnvironment())],
            link: "https://" + (self.getPackageDeploymentDomain())
          }
        }, function(err, response, body) {
          return done(err);
        });
      };
    },
    doDocDeploymentNotification: function() {
      return function(done) {
        request({
          uri: 'https://api.flowdock.com/v1/messages/team_inbox/87d6d03d770e3ea007f7fe747fede5f4',
          method: 'POST',
          json: {
            source: 'Circle',
            from_address: 'deploy+ok@joukou.com',
            subject: "Success: deployment of " + (self.getName()) + "doc to " + (self.getDocDeploymentDomain()) + " from build \#" + (self.getBuildNum()),
            content: "<b>" + (self.getName()) + "doc</b> deployed to <a href=\"https://" + (self.getDocDeploymentDomain()) + "\">" + (self.getDocDeploymentDomain()) + "</a>",
            from_name: '',
            project: self.getName().replace('-', ' '),
            tags: ['#deploy', "\#" + (self.getDeploymentEnvironment()), "#documentation"],
            link: "https://" + (self.getDocDeploymentDomain())
          }
        }, function(err, response, body) {
          return done(err);
        });
      };
    }
  };
};

/*
//# sourceMappingURL=index.js.map
*/
