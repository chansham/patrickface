"""Read-only checks of the new integration gates using an existing real source."""
import copy,unittest
import review_batch as batch

class IntegrationGates(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog=batch.read(batch.ROOT/'animation/candidates.json')
        raw=next(c for c in cls.catalog['clips']if c['id']=='sport-towel-first-20261012')
        cls.spec={'id':'fixture-only-not-written','source':raw['atlas'],'sha256':raw['sha256'],'columns':4,'rows':2,
                  'frameIndices':list(range(8)),'durationsMs':raw['durationsMs'],'frameLabels':raw['frameLabels'],
                  'status':'candidate-ready','visualReview':{'sourceViewed':True,'blackWhiteViewed':True,'alignmentReviewed':True},
                  'bodyQC':'animation/production-20261012-wardrobe/sport-towel-v2-body-qc.json','fixedSourcePixelToStagePixel':1.35,
                  'title':'fixture','description':'fixture','newOutfit':True,'comparisonClipId':'exercise','variantGroup':'fixture','pose':'standing','scaleReason':'fixture'}
        cls.qc=batch.inspect(cls.spec,False)

    def test_real_source_keeps_fixed_factor_and_is_never_approved(self):
        actual=batch.candidate(self.spec,self.qc,self.catalog)
        self.assertAlmostEqual(actual['scale']*665.6/self.qc['canvas']['width'],1.35)
        self.assertFalse(actual['artApproved']);self.assertEqual(actual['status'],'quality-revision-required')

    def test_prior_candidate_change_is_detected(self):
        batch.verify_baseline(self.catalog)
        changed=copy.deepcopy(self.catalog);changed['clips'][0]['scale']+=0.001
        with self.assertRaisesRegex(ValueError,'prior candidate changed'):batch.verify_baseline(changed)

    def test_changed_source_identity_is_rejected(self):
        spec=copy.deepcopy(self.spec);spec['sha256']='0'*64
        with self.assertRaisesRegex(ValueError,'source changed'):batch.inspect(spec,False)

    def test_other_sources_landmarks_cannot_apply(self):
        spec=copy.deepcopy(self.spec);spec['bodyQC']='animation/production-20261012-wardrobe/raincoat-v3-body-qc.json'
        with self.assertRaisesRegex(ValueError,'another source'):batch.candidate(spec,self.qc,self.catalog)

    def test_unreviewed_source_is_not_candidate(self):
        spec=copy.deepcopy(self.spec);spec['visualReview']['alignmentReviewed']=False
        with self.assertRaisesRegex(ValueError,'review missing'):batch.candidate(spec,self.qc,self.catalog)

    def test_repeated_drawing_cannot_be_counted_as_new_frame(self):
        spec=copy.deepcopy(self.spec);spec['frameIndices']=[0]*8
        with self.assertRaisesRegex(ValueError,'actual drawing once'):batch.candidate(spec,self.qc,self.catalog)

    def test_oversized_whole_clip_is_rejected_before_integration(self):
        spec=copy.deepcopy(self.spec);spec['fixedSourcePixelToStagePixel']=3
        with self.assertRaisesRegex(ValueError,'crosses .* stage'):batch.candidate(spec,self.qc,self.catalog)

if __name__=='__main__':unittest.main()
