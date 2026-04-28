import { readdir } from "fs/promises";
import { Command } from "commander";
import { consola } from "consola";

const runCLI = () => {
  const program = new Command();
  program
    .name("eot")
    .description("dir view tool")
    .version("1.0.0")
    .argument("[dir]")
    .action(async (dir) => {
      if (dir === undefined) {
        const dirname = await readdir(".");
        for (const dirlist of dirname) {
          consola.log("list");
          consola.log("-------------------------------");
          consola.log(dirlist);
        }
      } else {
        const dirname = await readdir(dir);
        for (const dirlist of dirname) {
          consola.log("list");
          consola.log("-------------------------------");
          consola.log(dirlist);
        }
      }
    });
};

