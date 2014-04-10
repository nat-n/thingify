'use strict'

angular.module('thingifyApp')

.controller 'MainCtrl', ($scope, workflowHelper, thingiverseAPI, $filter, $http, $window) ->
  # fetch the client id from the backend
  $http.get("/client_id").then (res) -> $scope.client_id = res.data.client_id

  # check for a code in the querystring
  codeMatch = /code=?([^&]*)/.exec(window.location.search.slice(1))
  $scope.code = codeMatch and codeMatch[1]

  # get access_token via the backend if we have a code
  if $scope.code
    auth_req = $http.get("/auth?code=#{$scope.code}")
    auth_req.then (res) ->
      token_match = /access_token=(.*?)&/.exec(res.data)
      if token_match
        $scope.token = token_match[1]
        workflowHelper.set_access_token($scope.token)
        thingiverseAPI.collections_by_user($scope.token).then (res)->
          console.log res.data
          $scope.collections = {}
          for coll in res.data
            $scope.collections[coll.id] = coll.name
      else
        $scope.code = null
        window.location.search = ''
    auth_req.error ->
      alert('Uh oh: Authorization failed')

  $scope.files = []

  $scope.$watch 'input_files', (files) ->
    return unless files
    i = -1
    $scope.files = ({
                      name: f.name.split('.')[0]
                      size: f.size
                      i: i+=1
                      file: f
                      tv_obj: null
                      status: 'Selected'
                    } for f in files)

  thingify_workflow = (file, thing_data) ->
    new_thing = _.cloneDeep(thing_data)
    new_thing.name = file.name

    workflowHelper.create_thing(file, new_thing)
    .then (file) ->
      workflowHelper.request_upload(file)
    .then (file) ->
      uf = workflowHelper.upload_file(file)
      uf.then (file) ->

        workflowHelper.finalize_upload(file)
        .finally (file) ->

          workflowHelper.publish_thing(file)
          .finally ->

            unless file.finalized
              workflowHelper.finalize_upload(file)
              .finally ->

                if file.published
                  file.status = 'Published'
                else
                  # some retries of stuff that shouldn't really fail but does
                  workflowHelper.publish_thing(file)
                  workflowHelper.finalize_upload(file) unless file.finalized

  $scope.thingify = (event, thing_data) ->
    # clear the files input element
    filesInput.value = []

    publish_thing = thing_data.publish
    thing_collection = thing_data.collection

    console.log 'thing_collection', thing_collection

    # restrict thing_data to valid params
    valid_params = ['name', 'license', 'category', 'description', 'instructions', 'is_wip', 'tags', 'ancestors']

    # transform and cleanup tags
    delete thing_data.param for param in thing_data when param not in valid_params
    thing_data.tags = thing_data.tags.split(/\s*,\s*/) if _.isString(thing_data.tags)
    delete thing_data.tags unless thing_data.tags.join('')

    # create todo list of files in this batch
    fileIDs = _.range($scope.files.length)

    # maintain an activity pool of up to `active_max` things in progress
    active_max = 3
    count_active_things = () ->
      ($filter('thingStatus')($scope.files, 'inProgress')).length
    $scope.$watch (-> fileIDs.length and count_active_things()), (activity) ->
      if activity < active_max and fileIDs.length
        thingify_workflow($scope.files[fileIDs.shift()], thing_data)


# bind multiple file upload input tag to a model
.directive 'filesModel', ($parse) ->
  restrict: 'A'
  link: (scope, element, attrs) ->
    model = $parse(attrs.filesModel)
    element.bind 'change', ->
      scope.$apply -> model.assign(scope, element[0].files)


.filter 'thingStatus', ->
  result = []
  filter = (file, status) ->
    status is 'selected' and  file.status is 'Selected' or
    status is 'inProgress' and file.status in [
      'Creating', 'Created',
      'Pre-registering upload', 'Pre-registered Upload',
      'Uploading', 'Uploaded',
      'Finalizing Upload', 'Upload Finalized',
      'Publishing Thing'] or
    status is 'completed' and file.status is 'Published' or
    status is 'error' and file.status in [
      'Failed Creation',
      'Failed Upload Pre-registration',
      'Failed Upload',
      'Deleting Thing',
      'Thing Deleted',
      'Delete Failed'
    ]
  (files, status) ->
    result.length = 0
    result.push file for file in files when filter(file, status)
    result
