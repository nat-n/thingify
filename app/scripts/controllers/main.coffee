'use strict'

angular.module('thingifyApp')

.controller 'MainCtrl', ($scope, workflowHelper, thingiverseAPI, $filter, $http, $window, $q) ->
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
          $scope.collections = {}
          for coll in res.data
            $scope.collections[coll.id] = coll.name
      else
        $scope.code = null
        window.location.search = ''
    auth_req.error ->
      alert('Uh oh: Authorization failed')

  $scope.files = []

  file_index_counter = -1
  $scope.$watch 'input_files', (files) ->
    return unless files
    $scope.files = $scope.files.concat ({
      name: f.name.split('.')[0]
      size: f.size
      i: file_index_counter+=1
      file: f
      tv_obj: null
      status: 'Selected'
      uploaded: false
      finalized: false
      published: false
      collected: false
    } for f in files)


  finalize_work = (file, remaining_attempts) ->
    # this function is for the less linear parts of the workflow after uploading
    # which involve simple requests that dont have to be done in order and
    # can easily be retried in any order if they fail.
    remaining_attempts = 5 if remaining_attempts is undefined

    if file.finalized and (file.published or not file.to_publish) and (file.collected or not file.for_collection)
      return file.status = 'Complete'

    if file.finalized
      defers = {}
      console.log '-', JSON.stringify(file)

      if file.to_publish and not file.published
        defers.published = undefined
        d = workflowHelper.publish_thing(file)
        d.then  -> defers.published = 'done'
        d.error -> defers.published = 'fail'

      if file.for_collection and not file.collected
        defers.collected = undefined
        d = workflowHelper.add_thing_to_collection(file)
        d.then  -> defers.collected = 'done'
        d.error -> defers.collected = 'fail'

      watch = $scope.$watch (->JSON.stringify(defers)), () ->
        console.log 'defers', JSON.stringify(defers)
        if (file.published or not file.to_publish) and (file.collected or not file.for_collection)
          console.log 'comp'
          file.status = 'Complete'
          watch()

        else if _.all (defers[d] for d of defers) # all promises resolved or rejected
          console.log 'remaining_attempts', remaining_attempts

          if remaining_attempts > 0
            unless (file.published and (file.collected or not file.for_collection))
              setTimeout -> finalize_work(file, remaining_attempts-1)
          else
            if d.published is 'fail'
              if d.collected is 'done'
                file.status = 'Uploaded but not published'
              else
                file.status = 'Uploaded but not published or added to collection'

            else if d.collected is 'fail'
                file.status = 'Published but not added to collection'
          watch()

    else if remaining_attempts
      d = workflowHelper.finalize_upload(file)
      d.then ->
        finalize_work(file, remaining_attempts)
      d.error ->
        finalize_work(file, remaining_attempts-1)
    else
      # what if not finalized???
      # then failed and delete??


  thingify_workflow = (file, thing_data) ->
    new_thing = _.cloneDeep(thing_data)
    new_thing.name = file.name

    workflowHelper.create_thing(file, new_thing)
    .then (file) ->
      workflowHelper.request_upload(file)
    .then (file) ->
      uf = workflowHelper.upload_file(file)
      uf.then (file) ->
        finalize_work(file)
      uf.catch () ->
        workflowHelper.delete_thing(file)

  $scope.thingify = (event, thing_data) ->
    # clear the files input element
    filesInput.value = []

    # restrict thing_data to valid params
    valid_params = ['name', 'license', 'category', 'description', 'instructions', 'is_wip', 'tags', 'ancestors']

    # transform and cleanup tags
    delete thing_data.param for param in thing_data when param not in valid_params
    thing_data.tags = thing_data.tags.split(/\s*,\s*/) if _.isString(thing_data.tags)
    delete thing_data.tags if thing_data.tags and not thing_data.tags.join('')

    # create todo list of files in this batch
    fileIDs = (f.i for f in $scope.files when f.status is 'Selected')

    # maintain an activity pool of up to `active_max` things in progress
    active_max = 3
    count_active_things = () ->
      ($filter('thingStatus')($scope.files, 'inProgress')).length
    watch = $scope.$watch (-> fileIDs.length and count_active_things()), (activity) ->
      if activity < active_max and fileIDs.length
        next_file = $scope.files[fileIDs.shift()]
        next_file.to_publish = thing_data.publish
        next_file.for_collection = thing_data.collection or false
        thingify_workflow(next_file, thing_data)
      watch() if fileIDs.length is 0



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
      'Publishing Thing', 'Published',
      'Adding thing to collection', 'Added to collection'] or
    status is 'completed' and file.status is 'Complete' or
    status is 'error' and file.status in [
      'Failed Creation',
      'Failed Upload Pre-registration',
      'Failed Upload',
      'Deleting Thing',
      'Thing Deleted',
      'Delete Failed',
      'Publish failed',
      'Failed add to collection',
      'Upload and added to collection but publish failed',
      'Upload finalize failed',
      'Uploaded but not published',
      'Uploaded but not published or added to collection',
      'Published but not added to collection'
    ]
  (files, status) ->
    result.length = 0
    result.push file for file in files when filter(file, status)
    result
