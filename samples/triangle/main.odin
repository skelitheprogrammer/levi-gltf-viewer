package main

import levi "../../src"
import "core:log"
import "core:os"

main :: proc() {
	context.logger = log.create_console_logger(.Info)
	defer log.destroy_console_logger(context.logger)

	log.info("levi viewer starting")

	app: levi.Application
	if err := levi.init(&app); err != .None {
		log.error("fatal", "code", err)
		os.exit(1)
	}
	defer levi.destroy(&app)

	if len(os.args) > 1 do levi.queue_asset_load(&app, os.args[1])

	levi.run(&app)
}
