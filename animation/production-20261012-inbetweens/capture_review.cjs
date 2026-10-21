const path=require('node:path');
process.env.QA_BATCH_DIR=__dirname;
process.env.QA_OUTPUT=process.env.QA_OUTPUT||path.resolve(__dirname,'../../output/playwright/inbetweens-20261012/browser');
require('../production-20261012-fitness/capture_review.cjs');
