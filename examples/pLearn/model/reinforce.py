#!/usr/bin/env python3


import argparse
import numpy as np
from keras.models import load_model
from trained.topModel.environment import Constants

from RLquaticus.bridge import ModelBridgeServer
from RLquaticus.util.display import ModelConsole
from state import make_state

from util.validate import check_model_dir
from util.constants import PLEARN_ACTIONS, PLEARN_TOPMODEL, ENEMY_FLAG
from util.state import state2vec, dist

def run_model(args):
    const = Constants()
    models = {}

    print('Loading model...')
    if const.alg_type == "fitted":
        for a in PLEARN_ACTIONS:
            models[a] = load_model(f'{args.model}/{a}.h5')
    else:
        raise TypeError(f'Unimplmented pLearn algorithm "{const.alg_type}"')

    print('Starting server...')
    with ModelBridgeServer() as server:
        server.accept() # This will block until cleint connects

        MOOS_STATE = None
        model_state = None
        console = ModelConsole()
        while True:
            # Get state from BHV_Agent client and translate
            MOOS_STATE = server.listen_state()
            model_state = make_state(const.state, const.num_states, MOOS_STATE)
            state_vec = state2vec(model_state, const)

            # Find optimal action
            optimal = (0, None)
            for a in PLEARN_ACTIONS:
                value = models[a].predict(state_vec)

                if optimal[1] is None or optimal[0] < value:
                    optimal = (value, PLEARN_ACTIONS[a])

            # Send optimal action to BHV_Agent client
            action = optimal[1]
            if abs(dist((MOOS_STATE['NAV_X'], MOOS_STATE['NAV_Y']), ENEMY_FLAG)) < 10:
                action['MOOS_VARS'] = {
                'FLAG_GRAB_REQUEST': f'vname={MOOS_STATE["VNAME"]}'
                }

            server.send_action(optimal[1])

            console.tick(MOOS_STATE)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--model', default=PLEARN_TOPMODEL)
    
    args = parser.parse_args()

    check_model_dir(args.model)

    run_model(args)