using Assets.Scripts.Saves___Serialization.SaveFiles;
using HarmonyLib;
using MegabonkTogether.Helpers;
using System.Collections;

namespace MegabonkTogether.Patches
{
    [HarmonyPatch(typeof(ProgressionSaveFile))]
    internal static class ProgressionSaveFilePatches
    {
        /// <summary>
        /// Persist the run progression once the game over has been committed.
        /// A client can be sent back to the menu by the host before leaving its own death screen.
        /// </summary>
        [HarmonyPostfix]
        [HarmonyPatch(nameof(ProgressionSaveFile.OnGameOver))]
        public static void OnGameOver_Postfix()
        {
            CoroutineRunner.Instance.Run(FlushNextFrame());
        }

        /// <summary>
        /// Wait for every other game over listener to run before saving
        /// </summary>
        private static IEnumerator FlushNextFrame()
        {
            yield return null;
            SaveManagerPatches.FlushNetplayProgression("game over");
        }
    }
}
