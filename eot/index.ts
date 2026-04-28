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
      const target = dir ?? "./";
      const dirname = await readdir(target);
      consola.log("list");
      consola.log("-------------------------------");
      for (const dirlist of dirname) {
        consola.log(dirlist);
      }
    });

  program.parse();
};

runCLI();
