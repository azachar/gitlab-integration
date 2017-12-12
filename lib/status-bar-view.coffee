{CompositeDisposable} = require('atom')
log = require './log'

class StatusBarView extends HTMLElement
    init: ->
        @classList.add('status-bar-gitlab', 'inline-block')
        @activate()
        @currentProject = null
        @stages = {}
        @statuses = {}
        @tooltips = []

    activate: => @displayed = false
    deactivate: =>
        @disposeTooltips()
        @dispose() if @displayed

    onDisplay: (@display) ->
        if @displayed
            @display(@)

    onDispose: (@dispose) ->

    hide: =>
        @dispose() if @displayed
        @displayed = false

    show: =>
        if @display?
            @display(@) if not @displayed
        @displayed = true

    onProjectChange: (project) =>
        log "current project becomes #{project}"
        @currentProject = project
        if project?
            if @stages[project]?
                @update(project, @stages[project])
            else if @statuses[project]?
                @loading(project, @statuses[project])
            else
                @unknown(project)

    onStagesUpdate: (stages) =>
        log "new stages", stages
        @stages = stages
        if @stages[@currentProject]?
            @update(@currentProject, @stages[@currentProject])

    disposeTooltips: =>
        @tooltips.forEach((tooltip) => tooltip.dispose())
        @tooltips = []

    loading: (project, message) =>
        log "project #{project} loading with status '#{message}'"
        @statuses[project] = message
        server = atom.config.get('gitlab-integration.server')
        if @currentProject is project
            @show()
            @disposeTooltips()
            status = document.createElement('div')
            status.classList.add('inline-block')
            icon = document.createElement('a')
            icon.classList.add('icon', 'icon-gitlab')
            icon.href = "#{server}/#{project}/pipelines/"
            @tooltips.push atom.tooltips.add icon, {
                title: "GitLab project #{project}"
            }
            span = document.createElement('span')
            span.classList.add('icon', 'icon-sync', 'icon-loading')
            @tooltips.push atom.tooltips.add(span, {
                title: message,
            })
            status.appendChild icon
            status.appendChild span
            @setchild(status)

    setchild: (child) =>
        if @children.length > 0
            @replaceChild child, @children[0]
        else
            @appendChild child

    update: (project, stages) =>
        log "updating stages of project #{project} with", stages
        @show()
        @disposeTooltips()
        status = document.createElement('div')
        status.classList.add('inline-block')
        icon = document.createElement('a')
        icon.classList.add('icon', 'icon-gitlab')
        server = atom.config.get('gitlab-integration.server')
        icon.href = "#{server}/#{project}/pipelines"
        @tooltips.push atom.tooltips.add icon, {
            title: "GitLab project #{project}"
        }
        status.appendChild icon
        if stages.length is 0
            e = document.createElement('span')
            e.classList.add('icon', 'icon-question')
            @tooltips.push atom.tooltips.add e, {
                title: "no pipeline found"
            }
            status.appendChild e
        else
            icon.href = "#{server}/#{project}/pipelines/#{stages[0].pipeline}"
            stages.forEach((stage) =>
                e = document.createElement('a')
                e.classList.add('icon', "gitlab-#{stage.status}")
                if stage.firstFailedJob
                  e.href = "#{server}/#{project}/-/jobs/#{stage.firstFailedJob.id}"
                @tooltips.push atom.tooltips.add e, {
                    title: "#{stage.name}: #{stage.status}"
                }
                status.appendChild e
            )
        @setchild(status)

    unknown: (project) =>
        log "project #{project} is unknown"
        @statuses[project] = undefined
        if @currentProject is project
            @show()
            @disposeTooltips()
            status = document.createElement('div')
            status.classList.add('inline-block')
            span = document.createElement('span')
            span.classList.add('icon', 'icon-question')
            status.appendChild span
            @tooltips.push atom.tooltips.add(span, {
                title: "no GitLab project detected in #{project}"
            })
            @setchild(status)

module.exports = document.registerElement 'status-bar-gitlab',
    prototype: StatusBarView.prototype, extends: 'div'
