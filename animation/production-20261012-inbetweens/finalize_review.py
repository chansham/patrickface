from batch_tools import batch,load,HERE
engine=load('finalize_review');engine.HERE=HERE;engine.OUTPUT_SLUG='inbetweens-20261012'
# Count only selected successful sources. The engine still rejects an empty or unfinished batch.
engine.EXPECTED_CLIP_COUNT=len(batch.read(HERE/'manifest.json')['sources'])
if __name__=='__main__':engine.main()
