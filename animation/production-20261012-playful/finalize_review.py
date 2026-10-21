from batch_tools import batch,load,HERE
engine=load('finalize_review');engine.HERE=HERE;engine.OUTPUT_SLUG='playful-20261012';engine.EXPECTED_CLIP_COUNT=2
if __name__=='__main__':engine.main()
