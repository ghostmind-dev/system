import { GoogleGenAI } from 'npm:@google/genai';
import * as fs from 'node:fs';
import * as path from 'node:path';

interface GenerateImageOptions {
  prompt: string;
  imagePath?: string;
  outputPath?: string;
}

async function generateImage(options: GenerateImageOptions): Promise<string> {
  const ai = new GoogleGenAI({});

  const contents: Array<
    { text: string } | { inlineData: { mimeType: string; data: string } }
  > = [{ text: options.prompt }];

  // If an input image is provided, include it for image-to-image generation
  if (options.imagePath) {
    const imageData = fs.readFileSync(options.imagePath);
    const base64Image = imageData.toString('base64');
    const ext = path.extname(options.imagePath).toLowerCase();
    const mimeType =
      ext === '.jpg' || ext === '.jpeg'
        ? 'image/jpeg'
        : ext === '.png'
        ? 'image/png'
        : ext === '.webp'
        ? 'image/webp'
        : ext === '.gif'
        ? 'image/gif'
        : 'image/png';

    contents.push({
      inlineData: {
        mimeType,
        data: base64Image,
      },
    });
  }

  const response = await ai.models.generateContent({
    model: 'gemini-2.0-flash-exp',
    contents: contents,
    config: {
      responseModalities: ['Text', 'Image'],
    },
  });

  const outputPath = options.outputPath || 'generated-image.png';

  for (const part of response.candidates![0].content!.parts!) {
    if (part.text) {
      console.log('Response text:', part.text);
    } else if (part.inlineData) {
      const imageData = part.inlineData.data;
      const buffer = Buffer.from(imageData!, 'base64');
      fs.writeFileSync(outputPath, buffer);
      console.log(`Image saved as ${outputPath}`);
      return outputPath;
    }
  }

  throw new Error('No image was generated in the response');
}

// CLI interface
if (import.meta.main) {
  const args = Deno.args;

  if (args.length === 0) {
    console.log(
      'Usage: deno run --allow-read --allow-write --allow-net --allow-env generate-image.ts <prompt> [--input <image-path>] [--output <output-path>]'
    );
    console.log('');
    console.log('Examples:');
    console.log(
      '  deno run --allow-all generate-image.ts "A cat eating a nano-banana"'
    );
    console.log(
      '  deno run --allow-all generate-image.ts "Make this cat eat a banana" --input cat.png --output cat-banana.png'
    );
    Deno.exit(1);
  }

  const prompt = args[0];
  let imagePath: string | undefined;
  let outputPath: string | undefined;

  for (let i = 1; i < args.length; i++) {
    if (args[i] === '--input' && args[i + 1]) {
      imagePath = args[++i];
    } else if (args[i] === '--output' && args[i + 1]) {
      outputPath = args[++i];
    }
  }

  try {
    await generateImage({ prompt, imagePath, outputPath });
  } catch (error) {
    console.error('Error generating image:', error);
    Deno.exit(1);
  }
}

export { generateImage, type GenerateImageOptions };
