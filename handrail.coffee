#!/usr/bin/env casperjs

brocco = require '/home/pmasurel/git/handrailJS/vendor/brocco'
fs = require 'fs'
cs = require('/home/pmasurel/git/handrailJS/vendor/coffee-script.js').CoffeeScript

CASPER_CONFIG = 
    #clientScripts:  [ 'vendor/jquery-1.11.0.min.js' ]
    logLevel: "info"
    verbose: true    
casper = require('casper').create CASPER_CONFIG

split_data = (data)-> 
    limit = data.indexOf "---"
    header = data[...limit]
    body = data[limit+3...]
    [ header, body ]

casper.on 'http.status.400', (resource)->
    casper.log '400 ON ' + resource.url, 'error'

casper.on 'http.status.404', (resource)->
    casper.log '404 ON ' + resource.url, 'error'

casper.on 'remote.message', (msg)->
    casper.log '[ console ]' +  msg, 'info'



class Camera

    constructor: (@name, @output, @suffix)->
        @margin = 100
        @min_diameter = 200
        @viewport_width = 1100
        @viewport_height = 3000

    adjust_frame: (box)-> 
        throw "NOT IMPLEMENTED"

    shot_filepath: (name)->
        relpath = "img/" + name + @suffix + ".png"
        filepath = @output + "/" + relpath
        relpath: relpath
        filepath: filepath          

    get_box = (selector)->
        $el = $(selector)
        box = $el.offset()
        box.width = $el.outerWidth()
        box.height = $el.outerHeight()
        box

    shot: (casper, selector, name)->
        box = casper.evaluate get_box, selector
        frame = @adjust_frame box
        img_metas = @shot_filepath name
        casper.capture img_metas.filepath, frame
        img_metas.box = box
        img_metas.frame = frame
        img_metas


class FullCamera extends Camera

    adjust_frame: (box)-> 
        # y = box.top + box.height / 2.0
        # if y < 600
        #     y = 0
        # else
        #     y = Math.max (y - 500), box.top
        #     y = Math.min (@viewport_height - 1000), y
        left: 0
        top: 0
        width: @viewport_width
        height: 1000

class ZoomCamera extends Camera

    adjust_frame: (box)-> 
        x = box.left + box.width / 2.0
        y = box.top + box.height / 2.0
        diameter = Math.max(box.width, box.height) + @margin
        diameter = Math.max(diameter, @min_diameter)
        diameter = Math.min(diameter, @viewport_width, @viewport_height)
        left = Math.max(x - diameter/2.0, 0.0)
        top = Math.max(y - diameter/2.0, 0.0)
        left = Math.min(left, @viewport_width - diameter)
        top = Math.min(top, @viewport_height - diameter)
        left: left
        top: top
        width: diameter
        height: diameter

cameras = []


class Operation

    constructor: (@name, @options)->

    run: (casper)->
        throw "Not implemented"

    setup: (casper, step_output)->
        casper.then =>
            @run casper, step_output

class CheckOperation extends Operation

    run: (casper)->
        check = casper.evaluate @code
        if not check
            console.error @name, ": failed, dying."
            casper.die()

class WaitOperation extends Operation

    success: ->
        casper.log 'WAITED ' + @name, 'info'

    failure: ->
        casper.log 'TIMEOUT ' + @name, 'error'
        [condition, args] = @condition_and_args()
        casper.die()

    condition_and_args: ->
        condition = @options.condition
        args = @options.args 
        if not condition? and @options.selector
            condition = (selector)-> $(selector).length >= 1
            args = [ @options.selector ]
        if not args?
            args = []
        [condition, args]

    run: (casper)->
        timeout = @options.timeout ? 5000
        [condition, args] = @condition_and_args()
        if condition?
            casper.waitFor (-> casper.evaluate(condition, args...)), (=> @success()), (=> @failure()), timeout
        else
            casper.wait timeout

class ActionOperation extends Operation
    
    run: (casper)->
        @options.apply casper


class ClickOperation extends Operation

    constructor: (@name, @options)->
        @subops = []
        timeout = @options.timeout ? 5000
        if @options.selector
            @subops.push new WaitOperation @name + "_wait",
                condition: (selector) -> $(selector).length >= 1
                args: [ @options.selector ]
                timeout: timeout
            selector = @options.selector
            @subops.push new ActionOperation @name+"_action", ->
                dummy_class = "handrail-" + (Math.random()  * 1000 | 0)
                add_class = (dummy_class, selector) ->
                    $el = $(selector)
                    $el.addClass dummy_class
                    JSON.stringify $el.length
                remove_class = (dummy_class) ->
                    $("." + dummy_class).removeClass dummy_class
                @evaluate(add_class, dummy_class, selector)
                if options.mousemove
                    @mouse.move("." + dummy_class)
                @click("." + dummy_class)
                @evaluate remove_class,  dummy_class
        else if @options.label?
            tag = @options.tag
            label = @options.label
            selector = (tag ? "*") + ":contains(#{label})"
            @subops.push new WaitOperation @name + "_wait",
                selector: selector
            @subops.push new ActionOperation @name+"_action", ->
                if tag?
                    @clickLabel label, tag
                else
                    @clickLabel label
        else
            throw "Cannot build click operation with " + JSON.stringify @options
    setup: (casper, step_output)->
        for op in @subops
            do (op)->
                casper.then ->
                    casper.log "  OPERATION : " + op.name, 'info'
                    op.run casper, step_output


class DebugOperation extends Operation
    
    run: (casper)->
        console.log "DEBUG(#{@name}) :" + casper.evaluate @options

class ScreenshotOperation extends Operation
    
    run: (casper, step_output)->
        selector = @options.selector
        #writer.append "<img class='circle' src='#{ img.relpath }'>"
        shots = {}
        screenshot = { "name": @name, "shots": shots }
        for camera in cameras
            console.log cameras.length
            console.log "shooting with" + camera.name
            img = camera.shot casper, selector, @name
            shots[camera.name] = img
        step_output.add_screenshot screenshot

operation_from_label = (opname)->
    for opprefix,opclass of OPERATION_MAP
        if opname.indexOf(opprefix) == 0
            return opclass
    undefined

class Step

    constructor: (@text)-> 
        @operations = []

    add_operation: (operation)->
        casper.log "Adding operation : " + operation.name, "info"
        @operations.push operation


class StepOuput

    constructor: (@id)->
        @screenshots = []
        @markdown = ""

    add_screenshot: (screenshot)->
        @screenshots.push screenshot

class Writer

    constructor: (@output)->
        @filepath = @output + "/index.json"
        @steps = []

    append_step: (step)->
        @steps.push step

    write: ->
        if @filepath?
            fs.write @filepath, JSON.stringify(this), 'w'


class Tutorial
    
    constructor: (@config, @steps)->

    start: ->
        writer = new Writer @config.output
        cameras = [
            new ZoomCamera("circle", @config.output, "-circle"),
            new FullCamera("full",   @config.output, "-full")
        ]
        steps_data = []
        casper.start @config.url, =>
            casper.viewport @config.width, @config.height
            for step_id, step of @steps
                step_output = new StepOuput(step_id)
                writer.append_step step_output
                do (step, step_id,step_output) ->
                    casper.then ->
                        console.log "------------"
                        casper.log "Step " + step_id, 'info'
                        console.log "------------"
                        console.log step.text
                        step_output.markdown = step.text
                    for operation in step.operations
                        operation.setup casper, step_output
                casper.then ->
                    writer.append_step JSON.parse(JSON.stringify(step_output))
            casper.then ->
                writer.write()
        casper.run()

    @from_file: (filepath, cb)->
        #    file in filepath into a tutorial object.
        data = fs.read filepath 
        [ header, body ] = split_data data
        config = cs.eval header
        steps = []
        # just a dummy name to make docco thinks its a litterate coffeescript file.
        new_step = null
        operation_appender = (name, optype)->
            window[name] = (params) ->
                op_name = params.name
                console.log op_name
                if not op_name? or op_name.length==0
                    op_name = name + "_" + (steps.length + 1) + "_" + (new_step.operations.length + 1)
                new_step.add_operation (new optype op_name, params)
        operation_appender "check", CheckOperation
        operation_appender "action", ActionOperation
        operation_appender "screenshot", ScreenshotOperation
        operation_appender "debug", DebugOperation
        operation_appender "wait", WaitOperation
        operation_appender "click", ClickOperation
        for stepData in brocco.parse "dummy.litcoffee", body
            new_step = new Step stepData.docsText
            if stepData.codeText?
                f = cs.compile stepData.codeText
                eval f
            steps.push new_step
        new Tutorial config, steps

if casper.cli.args.length != 1
    console.log "Expecting step markdown file as argument."
    casper.exit();
else
    filepath = casper.cli.args[0]
    Tutorial.from_file(filepath).start()
