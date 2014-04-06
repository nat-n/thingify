'use strict'

angular.module('thingifyApp')


.controller 'MainCtrl', ($scope, $http) ->

  $http.post
